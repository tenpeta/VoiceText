import Foundation

enum AppPaths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/VoiceText", isDirectory: true)
    static let rime = support.appendingPathComponent("Rime", isDirectory: true)
    static let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/VoiceText", isDirectory: true)
    static let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceText", isDirectory: true)
    static func prepare() throws {
        for url in [support, rime, logs, temporary] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        for url in try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("voicetext-") { try? FileManager.default.removeItem(at: url) }
    }
}


extension CredentialStore {
    static let shared = CredentialStore(
        file: AppPaths.support.appendingPathComponent("Credentials/credentials.json")
    )
}
