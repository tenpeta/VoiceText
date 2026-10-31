// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceTextCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "VoiceTextCore", targets: ["VoiceTextCore"])],
    targets: [
        .target(name: "NativeSupport", path: "NativeSupport", publicHeadersPath: "include",
                linkerSettings: [.linkedLibrary("z")]),
        .target(name: "VoiceTextCore", dependencies: ["NativeSupport"], path: "Sources",
                exclude: ["App", "CandidateUI", "InputMethod", "RimeEngine", "SettingsUI", "Storage/AppPaths.swift",
                          "Storage/AppSettings.swift",
                          "Voice/ASR/HTTPService.swift", "Voice/VoiceCoordinator.swift"],
                sources: ["Core", "Storage/HistoryStore.swift", "Storage/CredentialStore.swift", "Voice/ASR/Doubao/DoubaoProtocol.swift", "Voice/ASR/Doubao/DoubaoSession.swift",
                          "Voice/AudioCapture/WAVFile.swift", "Voice/AudioCapture/AudioCapture.swift"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "VoiceTextCoreTests", dependencies: ["VoiceTextCore"], path: "Tests", exclude: ["RimeSmoke.c"])
    ]
)
