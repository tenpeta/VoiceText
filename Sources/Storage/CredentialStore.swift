import Foundation

struct CredentialStore {
    let file: URL

    func read(_ account: String) throws -> String {
        try load()[account] ?? ""
    }

    func save(_ value: String, account: String) throws {
        var values = try load()
        if value.isEmpty { values.removeValue(forKey: account) }
        else { values[account] = value }
        let manager = FileManager.default
        let directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do { return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file)) }
        catch { throw VoiceTextError.message("无法读取本地密钥文件，请检查文件权限或恢复备份，原文件未被覆盖。") }
    }
}
