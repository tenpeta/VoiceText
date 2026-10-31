import Foundation

enum ASRProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case doubao, openAI, qwen
    var id: String { rawValue }
    var title: String {
        switch self { case .doubao: return "豆包流式语音识别"; case .openAI: return "OpenAI 语音转写"; case .qwen: return "千问 ASR" }
    }
    var defaultEndpoint: String {
        switch self {
        case .doubao: return "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
        case .openAI: return "https://api.openai.com/v1/audio/transcriptions"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
    }
    var defaultModel: String {
        switch self { case .doubao: return "volc.seedasr.sauc.duration"; case .openAI: return "gpt-transcribe"; case .qwen: return "qwen3-asr-flash" }
    }
}

struct ServiceConfiguration: Codable, Equatable, Sendable {
    var endpoint: String
    var model: String
    static func preset(_ provider: ASRProvider) -> Self {
        .init(endpoint: provider.defaultEndpoint, model: provider.defaultModel)
    }
    func url(streaming: Bool = false) throws -> URL {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == (streaming ? "wss" : "https"),
              url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else {
            throw VoiceTextError.message(streaming ? "请输入完整的 wss:// 接口地址。" : "请输入完整的 https:// 接口地址。")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceTextError.message("请填写模型或资源 ID。")
        }
        return url
    }
}

enum VoiceTextError: LocalizedError, Equatable {
    case message(String)
    case noSpeech
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .noSpeech: return "没有识别到语音。"
        }
    }
}

struct ASRResult: Sendable {
    let text: String
    let provider: ASRProvider
    let model: String
}

enum TextOffsets {
    static func utf16Offset(_ byteOffset: Int, in string: String) -> Int {
        let bytes = string.utf8
        let clamped = min(max(0, byteOffset), bytes.count)
        let position = bytes.index(bytes.startIndex, offsetBy: clamped)
        guard let index = String.Index(position, within: string) else { return 0 }
        return index.utf16Offset(in: string)
    }
}

