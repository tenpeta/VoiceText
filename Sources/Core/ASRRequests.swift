import Foundation

enum ASRRequests {
    static func qwenBody(wav: Data, model: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false,
            "messages": [["role": "user", "content": [["type": "input_audio", "input_audio": ["data": "data:audio/wav;base64," + wav.base64EncodedString()]]]]],
            "asr_options": ["enable_itn": true]
        ])
    }
    static func transcript(_ data: Data, provider: ASRProvider) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalid }
        let text: String?
        if provider == .openAI { text = json["text"] as? String }
        else {
            let choices = json["choices"] as? [[String: Any]]
            text = (choices?.first?["message"] as? [String: Any])?["content"] as? String
        }
        guard let text else { throw invalid }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceTextError.noSpeech }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
