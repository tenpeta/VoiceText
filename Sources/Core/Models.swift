import Foundation

enum ASRProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case doubao, qwen, tencent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .doubao: return "火山引擎"
        case .qwen: return "阿里云百炼"
        case .tencent: return "腾讯云"
        }
    }
    var defaultEndpoint: String {
        switch self {
        case .doubao: return "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
        case .qwen: return "wss://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
        case .tencent: return "wss://asr.cloud.tencent.com/asr/v2"
        }
    }
    var defaultModel: String {
        switch self {
        case .doubao: return "volc.seedasr.sauc.duration"
        case .qwen: return "qwen-audio-3.1-asr-flash-message"
        case .tencent: return "Hy-ASR-3.0-preview"
        }
    }
    var modelTitle: String {
        switch self {
        case .doubao: return "豆包流式语音识别 2.0"
        case .qwen: return "千问流式语音识别 3.1 Flash Message"
        case .tencent: return "混元语音识别 3.0 预览版"
        }
    }

    var modelID: String { self == .doubao ? "Doubao-Seed-ASR-2.0" : defaultModel }

    static func qwenConfiguration(workspaceID: String) throws -> ServiceConfiguration {
        let id = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: #"^[a-zA-Z0-9-]+$"#, options: .regularExpression) != nil else {
            throw VoiceTextError.message("请填写阿里云百炼华北2（北京）的业务空间 ID。")
        }
        return .init(endpoint: ASRProvider.qwen.defaultEndpoint.replacingOccurrences(of: "{WorkspaceId}", with: id),
                     model: ASRProvider.qwen.defaultModel)
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

