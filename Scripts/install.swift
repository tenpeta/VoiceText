import AppKit
import Carbon

let manager = FileManager.default
let bundleID = "im.voicetext.inputmethod.VoiceText"
let compatibleBundleIDs = [bundleID, "im.voicetext.inputmethod"]
let library = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
let destination = library.appendingPathComponent("Input Methods/VoiceText.app", isDirectory: true)
let supplied = CommandLine.arguments.dropFirst().first
let source = URL(fileURLWithPath: supplied ?? "build/DerivedData/Build/Products/Release/VoiceText.app").standardizedFileURL

func sourceIdentifier(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
do {
    guard Bundle(url: source)?.bundleIdentifier == bundleID else { throw NSError(domain: "VoiceText", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先构建 VoiceText.app。"] ) }
    if let selected = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), sourceIdentifier(selected)?.hasPrefix(bundleID) == true {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        guard let abc = list.first(where: { sourceIdentifier($0) == "com.apple.keylayout.ABC" }), TISSelectInputSource(abc) == noErr else {
            throw NSError(domain: "VoiceText", code: 2, userInfo: [NSLocalizedDescriptionKey: "请先切换到 ABC 输入法，再运行安装。"])
        }
    }
    let running = compatibleBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.filter { $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL }
    for app in running { _ = app.terminate() }
    let deadline = Date().addingTimeInterval(5)
    while running.contains(where: { !$0.isTerminated }), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    guard running.allSatisfy(\.isTerminated) else { throw NSError(domain: "VoiceText", code: 3, userInfo: [NSLocalizedDescriptionKey: "旧版输入法仍在运行，请退出登录后重试升级。"] ) }
    let updates = library.appendingPathComponent("Application Support/VoiceText/Updates")
    try manager.createDirectory(at: updates, withIntermediateDirectories: true)
    try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = updates.appendingPathComponent("Staging-\(UUID().uuidString).app")
    let previous = updates.appendingPathComponent("Previous.app")
    try manager.copyItem(at: source, to: staging)
    defer { try? manager.removeItem(at: staging) }
    let hadPrevious = manager.fileExists(atPath: destination.path)
    if hadPrevious {
        guard let installedID = Bundle(url: destination)?.bundleIdentifier, compatibleBundleIDs.contains(installedID) else { throw NSError(domain: "VoiceText", code: 4, userInfo: [NSLocalizedDescriptionKey: "目标位置存在其他应用，未进行覆盖。"] ) }
        if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
        try manager.moveItem(at: destination, to: previous)
        do { try manager.moveItem(at: staging, to: destination) }
        catch { try? manager.moveItem(at: previous, to: destination); throw error }
    } else { try manager.moveItem(at: staging, to: destination) }
    let registration = Process()
    registration.executableURL = destination.appendingPathComponent("Contents/MacOS/VoiceText")
    registration.arguments = ["--register"]
    try registration.run()
    registration.waitUntilExit()
    if registration.terminationStatus != 0 {
        let status = registration.terminationStatus
        try? manager.removeItem(at: destination)
        if hadPrevious {
            try manager.moveItem(at: previous, to: destination)
            let restore = Process()
            restore.executableURL = destination.appendingPathComponent("Contents/MacOS/VoiceText")
            restore.arguments = ["--register"]
            if (try? restore.run()) != nil { restore.waitUntilExit() }
        }
        throw NSError(domain: "VoiceText", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "输入源注册失败，已尝试恢复旧版本。"])
    }
    // Only clean historical artifacts after installation and registration succeed.
    do {
        for item in try manager.contentsOfDirectory(at: updates, includingPropertiesForKeys: nil) {
            let name = item.lastPathComponent
            if (name.hasPrefix("Previous-") && name.hasSuffix(".app")) ||
                (name.hasPrefix("Staging-") && name.hasSuffix(".app")) || name.hasPrefix("InputSourceCache-") {
                try manager.removeItem(at: item)
            }
        }
    } catch { fputs("更新已完成，但旧文件清理失败：\(error.localizedDescription)\n", stderr) }
    print("已安装到 \(destination.path)。请在系统设置中添加 VoiceText；首次安装若未出现，重新登录后再试。")
} catch { fputs("安装失败：\(error.localizedDescription)\n", stderr); exit(1) }
