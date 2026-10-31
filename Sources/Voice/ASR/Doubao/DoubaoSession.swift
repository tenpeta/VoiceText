import Foundation

// A small transport boundary permits deterministic end-packet/cancellation tests.
protocol DoubaoTransport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

final class DoubaoWebSocket: DoubaoTransport, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    init(request: URLRequest) {
        session = NetworkSession.make(resourceTimeout: 240)
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 8 * 1024 * 1024
    }
    func connect() async throws {
        socket.resume()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                socket.sendPing { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } catch {
            throw Self.connectionFailure(error, response: socket.response)
        }
    }

    static func connectionFailure(_ error: Error, response: URLResponse?) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return error }
        if let response = response as? HTTPURLResponse, response.statusCode >= 400 {
            do { try ASRRequests.check(response) }
            catch { return error }
        }
        if (error as? URLError)?.code == .badServerResponse {
            return VoiceTextError.message("豆包连接失败，请检查接口地址、鉴权方式、App ID / 密钥及资源 ID。")
        }
        return error
    }

    func send(_ data: Data) async throws { try await socket.send(.data(data)) }
    func receive() async throws -> Data {
        guard case .data(let bytes) = try await socket.receive() else {
            throw VoiceTextError.message("豆包返回了非预期的消息格式。")
        }
        return bytes
    }
    func close() { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
}

actor DoubaoSession {
    private let configuration: ServiceConfiguration
    private let key: String
    private let appID: String?
    private let makeTransport: @Sendable (URLRequest) -> DoubaoTransport
    private let finalTimeout: Duration
    private let sendTimeout: Duration
    private var transport: DoubaoTransport?
    private var receiver: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var waiter: CheckedContinuation<String, Error>?
    private var terminal: Result<String, Error>?
    private var pendingAudio: Data?
    private var stopping = false

    init(configuration: ServiceConfiguration, key: String, appID: String? = nil, finalTimeout: Duration = .seconds(30), sendTimeout: Duration = .seconds(5),
         makeTransport: @escaping @Sendable (URLRequest) -> DoubaoTransport = { DoubaoWebSocket(request: $0) }) {
        self.configuration = configuration; self.key = key; self.appID = appID; self.finalTimeout = finalTimeout; self.sendTimeout = sendTimeout; self.makeTransport = makeTransport
    }

    func start() async throws {
        let interval = Performance.voice.beginInterval("ConnectASR")
        defer { Performance.voice.endInterval("ConnectASR", interval) }
        try Task.checkCancellation()
        guard terminal == nil, transport == nil else { throw CancellationError() }
        let request = try Self.makeRequest(configuration: configuration, key: key, appID: appID)
        let transport = makeTransport(request)
        self.transport = transport
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)); await self?.complete(.failure(VoiceTextError.message("豆包连接超时，请检查网络和 API 配置。"))) }
            catch {}
        }
        do {
            try await transport.connect()
            if let terminal { _ = try terminal.get() }
            try await transport.send(DoubaoProtocol.request())
        } catch {
            complete(.failure(error)); throw recordedFailure ?? error
        }
        watchdog?.cancel(); watchdog = nil
        receiver = Task { [weak self] in await self?.receiveLoop() }
    }

    static func makeRequest(configuration: ServiceConfiguration, key: String, appID: String?) throws -> URLRequest {
        guard ["volc.seedasr.sauc.duration", "volc.seedasr.sauc.concurrent"].contains(configuration.model) else {
            throw VoiceTextError.message("请输入已开通的豆包 2.0 流式识别资源 ID（volc.seedasr.sauc.duration 或 volc.seedasr.sauc.concurrent）。")
        }
        guard !key.isEmpty else { throw VoiceTextError.message("请先保存豆包识别凭据。") }
        var request = URLRequest(url: try configuration.url(streaming: true), timeoutInterval: 10)
        if let appID {
            guard !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceTextError.message("请填写豆包旧版控制台的 App ID。")
            }
            request.setValue(appID.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "X-Api-App-Key")
            request.setValue(key, forHTTPHeaderField: "X-Api-Access-Key")
        } else {
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        }
        request.setValue(configuration.model, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        return request
    }

    func append(_ pcm: Data) async throws {
        try Task.checkCancellation()
        if let terminal { _ = try terminal.get(); throw VoiceTextError.message("豆包录音连接已结束。") }
        guard !stopping, let transport else { throw CancellationError() }
        // Keep one packet so the final marker carries the actual final audio packet.
        if let pendingAudio {
            let timeout = sendTimeout
            let sendingWatchdog = Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                    await self?.complete(.failure(VoiceTextError.message("音频发送超时，已停止录音，请检查网络后重试。")))
                } catch {}
            }
            defer { sendingWatchdog.cancel() }
            do { try await transport.send(DoubaoProtocol.audio(pendingAudio, final: false)) }
            catch { complete(.failure(error)); throw recordedFailure ?? error }
        }
        pendingAudio = pcm
    }

    func finish() async throws -> ASRResult {
        guard !stopping, let transport else { throw CancellationError() }
        stopping = true
        if let terminal { return .init(text: try terminal.get(), provider: .doubao, model: configuration.model) }
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: self?.finalTimeout ?? .seconds(30)); await self?.complete(.failure(VoiceTextError.message("豆包最终识别结果等待超时。"))) }
            catch {}
        }
        do { try await transport.send(DoubaoProtocol.audio(pendingAudio ?? Data(), final: true)) }
        catch { complete(.failure(error)); throw recordedFailure ?? error }
        pendingAudio = nil
        let text = try await withTaskCancellationHandler {
            if let terminal { return try terminal.get() }
            return try await withCheckedThrowingContinuation { waiter = $0 }
        } onCancel: { Task { await self.cancel() } }
        return .init(text: text, provider: .doubao, model: configuration.model)
    }

    func cancel() { complete(.failure(CancellationError())) }
    private var recordedFailure: Error? {
        if case .failure(let error)? = terminal { return error }
        return nil
    }

    private func receiveLoop() async {
        guard let transport else { return }
        do {
            while !Task.isCancelled {
                let bytes = try await transport.receive()
                let response = try DoubaoProtocol.parse(bytes)
                if response.final {
                    guard stopping else { throw VoiceTextError.message("豆包连接在停止录音前已结束，请重新录音。") }
                    guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                        throw VoiceTextError.noSpeech
                    }
                    complete(.success(text)); return
                }
            }
        } catch { complete(.failure(error)) }
    }
    private func complete(_ result: Result<String, Error>) {
        guard terminal == nil else { return }
        terminal = result
        let continuation = waiter; waiter = nil
        watchdog?.cancel(); watchdog = nil
        transport?.close(); transport = nil
        receiver?.cancel(); receiver = nil
        pendingAudio = nil
        continuation?.resume(with: result)
    }
}
