import Foundation

enum ASRRequests {
    static func qwenBody(wav: Data, model: String) throws -> Data {
        let audio = ["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + wav.base64EncodedString()]] as [String: Any]
        return try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": ["messages": [["role": "user", "content": [audio]]]],
            "parameters": ["format": "wav", "sample_rate": "16000"]
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
