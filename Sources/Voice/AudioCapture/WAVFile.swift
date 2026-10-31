import Foundation

final class WAVFile {
    let url: URL
    private var handle: FileHandle?
    private(set) var byteCount = 0

    init(directory: URL = FileManager.default.temporaryDirectory) throws {
        url = directory.appendingPathComponent("voicetext-\(UUID().uuidString).wav")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: 44),
                                              attributes: [.posixPermissions: 0o600]) else {
            throw VoiceTextError.message("无法创建临时录音文件。")
        }
        handle = try FileHandle(forWritingTo: url)
        try handle?.seekToEnd()
    }
    func append(_ pcm: Data) throws {
        guard let handle else { throw VoiceTextError.message("录音文件已关闭。") }
        try handle.write(contentsOf: pcm)
        byteCount += pcm.count
    }
    func finish() throws {
        guard let handle else { return }
        var header = Data("RIFF".utf8)
        header.appendLE(UInt32(36 + byteCount)); header.append(contentsOf: "WAVEfmt ".utf8)
        header.appendLE(UInt32(16)); header.appendLE(UInt16(1)); header.appendLE(UInt16(1))
        header.appendLE(UInt32(16000)); header.appendLE(UInt32(32000))
        header.appendLE(UInt16(2)); header.appendLE(UInt16(16))
        header.append(contentsOf: "data".utf8); header.appendLE(UInt32(byteCount))
        try handle.seek(toOffset: 0); try handle.write(contentsOf: header)
        try handle.close(); self.handle = nil
    }
    func remove() {
        try? handle?.close(); handle = nil
        try? FileManager.default.removeItem(at: url)
    }
    deinit { remove() }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ number: T) {
        var value = number.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
