import Foundation

actor QwenSession {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private let model: String
    private let taskID = UUID().uuidString
    private var receiver: Task<String, Error>?
    private var failure: Error?

    init(configuration: ServiceConfiguration, key: String) throws {
        var request = URLRequest(url: try configuration.url(streaming: true))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let session = NetworkSession.make(resourceTimeout: 240)
        self.session = session
        socket = session.webSocketTask(with: request)
        model = configuration.model
    }

    func start(polish: Bool, hotwords: [String]) async throws {
        socket.resume()
        let timeout = watchdog(.seconds(10), message: "百炼连接超时，请检查网络和语音识别配置。")
        defer { timeout.cancel() }
        do {
            try await socket.send(.string(ASRRequests.qwenStart(taskID: taskID, model: model, polish: polish, hotwords: hotwords)))
            guard try await receive().header.event == "task-started" else {
                throw VoiceTextError.message("百炼未确认启动识别任务。")
            }
            try Task.checkCancellation()
            receiver = Task { try await self.receiveTranscript() }
        } catch { throw failure ?? error }
    }

    func append(_ pcm: Data) async throws {
        if let failure { throw failure }
        let timeout = watchdog(.seconds(5), message: "百炼音频发送超时，请检查网络后重试。")
        defer { timeout.cancel() }
        do { try await socket.send(.data(pcm)) }
        catch { throw failure ?? error }
    }

    func finish() async throws -> ASRResult {
        if let failure { throw failure }
        guard let receiver else { throw CancellationError() }
        let timeout = watchdog(.seconds(30), message: "百炼最终识别结果等待超时。")
        defer { timeout.cancel() }
        do {
            try await socket.send(.string(ASRRequests.qwenCommand("finish-task", taskID: taskID, payload: ["input": [:]])))
            return .init(text: try await receiver.value, provider: .qwen, model: model)
        } catch { throw failure ?? error }
    }

    func cancel() {
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        receiver?.cancel()
        receiver = nil
    }

    private func receiveTranscript() async throws -> String {
        var sentences: [Int: String] = [:]
        do {
            while true {
                let response = try await receive()
                switch response.header.event {
                case "result-generated":
                    if let sentence = response.payload?.output?.sentence,
                       sentence.sentenceEnd, sentence.heartbeat != true {
                        sentences[sentence.sentenceID] = sentence.text
                    }
                case "task-finished":
                    return try ASRRequests.validatedText(sentences.sorted { $0.key < $1.key }.map(\.value).joined())
                default: break
                }
            }
        } catch {
            if failure == nil { failure = error }
            cancel()
            throw error
        }
    }

    private func receive() async throws -> QwenEvent {
        guard case .string(let json) = try await socket.receive() else {
            throw VoiceTextError.message("百炼返回了非预期的消息格式。")
        }
        let event = try JSONDecoder().decode(QwenEvent.self, from: Data(json.utf8))
        if event.header.event == "task-failed" {
            throw VoiceTextError.message(event.header.errorMessage ?? "百炼语音识别任务失败。")
        }
        return event
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
}

struct QwenEvent: Decodable {
    let header: Header
    let payload: Payload?

    struct Header: Decodable {
        let event: String
        let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case event
            case errorMessage = "error_message"
        }
    }

    struct Payload: Decodable {
        let output: Output?
    }

    struct Output: Decodable {
        let sentence: Sentence?
    }

    struct Sentence: Decodable {
        let sentenceID: Int
        let text: String
        let sentenceEnd: Bool
        let heartbeat: Bool?

        enum CodingKeys: String, CodingKey {
            case text, heartbeat
            case sentenceID = "sentence_id"
            case sentenceEnd = "sentence_end"
        }
    }
}
