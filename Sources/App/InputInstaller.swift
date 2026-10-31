import AppKit
import Carbon

enum InputInstaller {
    static let identifier = "im.voicetext.inputmethod.VoiceText"
    static let compatibleIdentifiers = [identifier, "im.voicetext.inputmethod"]
    static var destination: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/VoiceText.app", isDirectory: true) }

    private static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return String(describing: Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue())
    }
    static var isSelected: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = property(source, kTISPropertyInputSourceID) else { return false }
        return id == identifier || id.hasPrefix(identifier + ".")
    }
    static func register(_ url: URL = destination) throws {
        let status = TISRegisterInputSource(url as CFURL)
        guard status == noErr else { throw VoiceTextError.message("输入源注册失败（\(status)）。") }
    }
    static func install() throws {
        let source = Bundle.main.bundleURL.standardizedFileURL
        guard source != destination.standardizedFileURL else { try register(); return }
        let manager = FileManager.default
        guard Bundle(url: source)?.bundleIdentifier == identifier else { throw VoiceTextError.message("安装包标识不正确。") }
        if manager.fileExists(atPath: destination.path) {
            guard let installedID = Bundle(url: destination)?.bundleIdentifier, compatibleIdentifiers.contains(installedID) else {
                throw VoiceTextError.message("安装位置已有其他应用，未进行覆盖。")
            }
        }
        if isSelected {
            let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
            guard let abc = sources.first(where: { property($0, kTISPropertyInputSourceID) == "com.apple.keylayout.ABC" }), TISSelectInputSource(abc) == noErr else {
                throw VoiceTextError.message("请先切换到其他输入法，再安装更新。")
            }
        }
        let running = compatibleIdentifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL }
        for app in running { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while running.contains(where: { !$0.isTerminated }), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard running.allSatisfy(\.isTerminated) else { throw VoiceTextError.message("旧版 VoiceText 仍在运行，请退出后重试。") }
        let updates = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VoiceText/Updates", isDirectory: true)
        try manager.createDirectory(at: updates, withIntermediateDirectories: true)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = updates.appendingPathComponent("Staging-\(UUID().uuidString).app")
        let backup = updates.appendingPathComponent("Previous-\(UUID().uuidString).app")
        try manager.copyItem(at: source, to: staging)
        defer { try? manager.removeItem(at: staging) }
        let hadPrevious = manager.fileExists(atPath: destination.path)
        if hadPrevious { try manager.moveItem(at: destination, to: backup) }
        do {
            try manager.moveItem(at: staging, to: destination)
            try register()
        } catch {
            try? manager.removeItem(at: destination)
            if hadPrevious { try? manager.moveItem(at: backup, to: destination); try? register() }
            throw error
        }
        // Registration succeeded: the replaced app is the only rollback copy to retain.
        do {
            let previous = updates.appendingPathComponent("Previous.app")
            if hadPrevious {
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: backup, to: previous)
            }
            try cleanupUpdates(at: updates)
        } catch { NSLog("VoiceText: 更新已完成，但旧文件清理失败：%@", error.localizedDescription) }
        NSWorkspace.shared.open(destination)
    }
    private static func cleanupUpdates(at directory: URL) throws {
        let manager = FileManager.default
        for item in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = item.lastPathComponent
            if (name.hasPrefix("Previous-") && name.hasSuffix(".app")) ||
                (name.hasPrefix("Staging-") && name.hasSuffix(".app")) || name.hasPrefix("InputSourceCache-") {
                try manager.removeItem(at: item)
            }
        }
    }
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
