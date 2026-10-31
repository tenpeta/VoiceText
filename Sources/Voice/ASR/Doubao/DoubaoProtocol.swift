import Foundation
import NativeSupport

enum DoubaoProtocol {
    struct Response: Equatable {
        let text: String?
        let final: Bool
    }

    static func request() throws -> Data {
        let body: [String: Any] = [
            "user": ["uid": "voicetext"],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true,
                        "enable_ddc": false, "show_utterances": false]
        ]
        return try frame(type: 1, flags: 0, serialization: 1, payload: JSONSerialization.data(withJSONObject: body))
    }

    static func audio(_ pcm: Data, final: Bool) throws -> Data {
        try frame(type: 2, flags: final ? 2 : 0, serialization: 0, payload: pcm)
    }

    private static func frame(type: UInt8, flags: UInt8, serialization: UInt8, payload: Data) throws -> Data {
        let compressed = try gzip(payload)
        var result = Data([0x11, type << 4 | flags, serialization << 4 | 1, 0])
        result.appendUInt32(UInt32(compressed.count))
        result.append(compressed)
        return result
    }

    static func parse(_ data: Data) throws -> Response {
        guard data.count >= 8, data[0] >> 4 == 1 else { throw invalidFrame }
        let headerSize = Int(data[0] & 15) * 4
        guard headerSize >= 4, headerSize <= data.count else { throw invalidFrame }
        let type = data[1] >> 4, flags = data[1] & 15
        var cursor = headerSize
        if type == 15 {
            let code = try data.readUInt32(at: &cursor)
            let size = Int(try data.readUInt32(at: &cursor))
            guard size <= data.count - cursor else { throw invalidFrame }
            // Do not surface arbitrary server bodies, which can echo credentials/audio.
            throw VoiceTextError.message("豆包识别失败（\(code)）。请检查服务权限、资源 ID 或稍后重试。")
        }
        guard type == 9, data[2] >> 4 == 1 else { throw invalidFrame }
        if flags & 1 != 0 { _ = try data.readUInt32(at: &cursor) }
        let size = Int(try data.readUInt32(at: &cursor))
        guard size <= data.count - cursor else { throw invalidFrame }
        var body = data.subdata(in: cursor..<(cursor + size))
        switch data[2] & 15 {
        case 0: break
        case 1: body = try gunzip(body)
        default: throw invalidFrame
        }
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw invalidFrame }
        if let code = json["code"] as? Int, code != 0 && code != 20_000_000 {
            throw VoiceTextError.message("豆包识别失败（\(code)）。")
        }
        let result = json["result"] as? [String: Any]
        return Response(text: result?["text"] as? String, final: flags & 2 != 0)
    }

    static func gzip(_ data: Data) throws -> Data { try compress(data, unpack: false) }
    static func gunzip(_ data: Data) throws -> Data { try compress(data, unpack: true) }
    private static func compress(_ data: Data, unpack: Bool) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var count = 0
        let status = data.withUnsafeBytes { bytes in
            (unpack ? vt_gunzip : vt_gzip)(bytes.bindMemory(to: UInt8.self).baseAddress, data.count, &output, &count)
        }
        guard status == 0, let output else { throw VoiceTextError.message("语音数据压缩格式无效或过大。") }
        defer { vt_free(output) }
        return Data(bytes: output, count: count)
    }
    private static let invalidFrame = VoiceTextError.message("豆包返回了无法解析的协议数据。")
}

extension Data {
    mutating func appendUInt32(_ number: UInt32) {
        var big = number.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
    func readUInt32(at cursor: inout Int) throws -> UInt32 {
        guard cursor >= 0, count - cursor >= 4 else { throw VoiceTextError.message("语音协议数据不完整。") }
        let value = self[cursor..<(cursor + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        cursor += 4
        return value
    }
}
