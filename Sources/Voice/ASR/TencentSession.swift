import CryptoKit
import Foundation

actor TencentSession {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private let model: String
    private var receiver: Task<String, Error>?
    private var failure: Error?
    private var finishing = false

    init(configuration: ServiceConfiguration, appID: String, secretID: String, secretKey: String) throws {
        let url = try Self.signedURL(configuration: configuration, appID: appID, secretID: secretID, secretKey: secretKey)
        let session = NetworkSession.make(resourceTimeout: 240)
        self.session = session
        socket = session.webSocketTask(with: url)
        model = configuration.model
    }

    static func signedURL(configuration: ServiceConfiguration, appID: String, secretID: String, secretKey: String,
                          timestamp: Int = Int(Date().timeIntervalSince1970), nonce: Int = Int.random(in: 1...Int(Int32.max)),
                          voiceID: String = UUID().uuidString) throws -> URL {
        let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretID = secretID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appID.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              secretID.range(of: #"^[a-zA-Z0-9]+$"#, options: .regularExpression) != nil,
              !secretKey.isEmpty else {
            throw VoiceTextError.message("请填写腾讯云 AppID、SecretId 并保存 SecretKey。")
        }

        let endpoint = try configuration.url(streaming: true).absoluteString
        let query = [
            "engine_model_type": configuration.model,
            "expired": String(timestamp + 600),
            "nonce": String(nonce),
            "secretid": secretID,
            "timestamp": String(timestamp),
            "voice_format": "1",
            "voice_id": voiceID
        ].sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let unsigned = "\(endpoint)/\(appID)?\(query)"
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(unsigned.dropFirst("wss://".count).utf8),
            using: SymmetricKey(data: Data(secretKey.utf8))
        )
        let encoded = Data(signature).base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        guard let encoded, let url = URL(string: "\(unsigned)&signature=\(encoded)") else {
            throw VoiceTextError.message("无法生成腾讯云识别请求。")
        }
        return url
    }

    func start() async throws {
        socket.resume()
        let timeout = watchdog(.seconds(10), message: "腾讯云连接超时，请检查网络和语音识别配置。")
        defer { timeout.cancel() }
        do { _ = try await receive() }
        catch { throw failure ?? error }
        try Task.checkCancellation()
        receiver = Task { try await self.receiveTranscript() }
    }

    func append(_ pcm: Data) async throws {
        if let failure { throw failure }
        let timeout = watchdog(.seconds(5), message: "腾讯云音频发送超时，请检查网络后重试。")
        defer { timeout.cancel() }
        do { try await socket.send(.data(pcm)) }
        catch { throw failure ?? error }
    }

    func finish() async throws -> ASRResult {
        if let failure { throw failure }
        guard let receiver else { throw CancellationError() }
        finishing = true
        let timeout = watchdog(.seconds(30), message: "腾讯云最终识别结果等待超时。")
        defer { timeout.cancel() }
        do {
            try await socket.send(.string(#"{"type":"end"}"#))
            return .init(text: try await receiver.value, provider: .tencent, model: model)
        } catch {
            throw failure ?? error
        }
    }

    func cancel() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        receiver?.cancel()
        receiver = nil
    }

    private func receiveTranscript() async throws -> String {
        var segments: [Int: String] = [:]
        do {
            while true {
                let response = try await receive()
                if let result = response.result, result.sliceType == 2 {
                    segments[result.index] = result.text
                }
                if response.final == 1 {
                    guard finishing else { throw VoiceTextError.message("腾讯云连接在录音结束前已关闭，请重新录音。") }
                    return try ASRRequests.validatedText(segments.sorted { $0.key < $1.key }.map(\.value).joined())
                }
            }
        } catch {
            if failure == nil { failure = error }
            cancel()
            throw error
        }
    }

    private func receive() async throws -> Response {
        guard case .string(let json) = try await socket.receive() else {
            throw VoiceTextError.message("腾讯云返回了非预期的消息格式。")
        }
        let response = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        guard response.code == 0 else {
            throw VoiceTextError.message("腾讯云语音识别失败（\(response.code)）\(response.message.map { "：\($0)" } ?? "")")
        }
        return response
    }

    private func watchdog(_ duration: Duration, message: String) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
                if failure == nil { failure = VoiceTextError.message(message) }
                cancel()
            } catch {}
        }
    }

    private struct Response: Decodable {
        let code: Int
        let message: String?
        let final: Int?
        let result: Segment?
    }

    private struct Segment: Decodable {
        let sliceType: Int
        let index: Int
        let text: String

        enum CodingKeys: String, CodingKey {
            case sliceType = "slice_type"
            case index
            case text = "voice_text_str"
        }
    }
}
