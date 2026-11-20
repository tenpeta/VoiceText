import Foundation

struct SpeechHotwords {
    static let limit = 128
    let words: [String]
    let skippedCount: Int

    init(_ text: String, provider: ASRProvider) {
        var words: [String] = []
        var skippedCount = 0
        for word in Self.entries(in: text) {
            if words.count < Self.limit && Self.isCompatible(word, provider: provider) {
                words.append(word)
            } else {
                skippedCount += 1
            }
        }
        self.words = words
        self.skippedCount = skippedCount
    }

    static func entries(in text: String) -> [String] {
        var seen: Set<String> = []
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func isCompatible(_ word: String, provider: ASRProvider) -> Bool {
        guard word.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
        switch provider {
        case .doubao:
            return true
        case .qwen:
            if word.utf8.allSatisfy({ $0 < 128 }) {
                return word.split(separator: " ").count <= 7
            }
            return word.count <= 15
        case .tencent:
            return word.count <= 30
                && word.rangeOfCharacter(from: .whitespaces) == nil
                && !word.contains(",") && !word.contains("|")
                && word.range(of: #"\p{Han}(?:.*\p{Han}){10}"#, options: .regularExpression) == nil
        }
    }
}

enum ASRRequests {
    static func qwenBody(wav: Data, model: String, hotwords: [String] = []) throws -> Data {
        let audio = ["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + wav.base64EncodedString()]] as [String: Any]
        var parameters: [String: Any] = ["format": "wav", "sample_rate": "16000"]
        if !hotwords.isEmpty {
            parameters["vocabulary"] = Dictionary(hotwords.map { ($0, 4) }, uniquingKeysWith: { first, _ in first })
        }
        return try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": ["messages": [["role": "user", "content": [audio]]]],
            "parameters": parameters
        ])
    }

    static func qwenTranscript(_ data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = json?["output"] as? [String: Any]
        return try validatedText(output?["text"] as? String)
    }

    static func chatTranscript(_ data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return try validatedText(message?["content"] as? String)
    }

    static func validatedText(_ text: String?) throws -> String {
        guard let text else { throw invalid }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceTextError.noSpeech }
        return trimmed
    }

    static func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw invalid }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw VoiceTextError.message("API 凭据无效或尚未开通该模型权限。")
        case 429: throw VoiceTextError.message("API 请求过多或额度不足，请稍后重试。")
        default: throw VoiceTextError.message("云端服务请求失败（HTTP \(response.statusCode)）。")
        }
    }
    private static let invalid = VoiceTextError.message("服务没有返回有效的识别文本。")
}
