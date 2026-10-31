import AppKit

enum ThemeMode: String, Codable, CaseIterable { case system, light, dark }
enum CandidateLayout: String, Codable, CaseIterable { case horizontal, vertical }
struct CandidateColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent
    }
    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

struct CandidateTuning: Codable, Equatable {
    var systemMaterial = true
    var blur = 0.9
    var opacity = 0.8
    var lightBackground = CandidateColor(0xFAFAFA)
    var darkBackground = CandidateColor(0x242424)
    var lightText = CandidateColor(0x202020)
    var darkText = CandidateColor(0xF5F5F5)
    var selection = CandidateColor(0x6155F5)
    var selectedText = CandidateColor(0xFFFFFF)
    var border = CandidateColor(0x000000)
    var borderOpacity = 0.8
    var borderWidth = 0.5
    var shadow = true
    var capsule = true
    var selectionRadius = 20.0
    var padding = 2.0
    var spacing = 1.0
    var rowPadding = 1.0
    var wordPadding = 5.0
    var width = 400.0
    var showNumbers = true
    var numberSize = 8.0
    var numberOpacity = 0.65
    var offsetX = -16.0
    var offsetY = 6.0
}

struct AppearanceSettings: Codable, Equatable {
    var candidateTuning: CandidateTuning? = nil
    var tuning: CandidateTuning {
        get { candidateTuning ?? CandidateTuning() }
        set { candidateTuning = newValue }
    }
    var theme: ThemeMode = .system
    var layout: CandidateLayout = .horizontal
    var fontName = "PingFangSC-Regular"
    var fontSize: Double = 16
    var cornerRadius: Double = 8
    var padding: Double = 4
    var spacing: Double = 2
}
struct SettingsValue: Codable {
    var simplified = true
    var asciiPunctuation = false
    var appearance = AppearanceSettings()
    var provider = ASRProvider.doubao
    var doubao = ServiceConfiguration.preset(.doubao)
    var doubaoLegacyAuth: Bool? = nil
    var doubaoAppID: String? = nil
    var openAI = ServiceConfiguration.preset(.openAI)
    var qwen = ServiceConfiguration.preset(.qwen)
    var cleanupEnabled = false
    var cleanup = ServiceConfiguration(endpoint: "https://api.openai.com/v1/chat/completions", model: "")
    var voiceKeyCode: UInt16 = 61 // Right Option
    var voiceModifiers: UInt = 0 // Retained to migrate the previous combination shortcuts.
    var voiceKeyName: String? = nil
    var service: ServiceConfiguration {
        get { switch provider { case .doubao: return doubao; case .openAI: return openAI; case .qwen: return qwen } }
        set { switch provider { case .doubao: doubao = newValue; case .openAI: openAI = newValue; case .qwen: qwen = newValue } }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var value: SettingsValue {
        didSet {
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "settings.v1") }
            NotificationCenter.default.post(name: .voiceTextSettingsChanged, object: nil)
        }
    }
    init() {
        if UserDefaults.standard.data(forKey: "settings.v1") == nil,
           let data = UserDefaults.standard.persistentDomain(forName: "im.voicetext.inputmethod")?["settings.v1"] as? Data {
            UserDefaults.standard.set(data, forKey: "settings.v1")
        }
        var loaded = UserDefaults.standard.data(forKey: "settings.v1")
            .flatMap { try? JSONDecoder().decode(SettingsValue.self, from: $0) } ?? SettingsValue()
        // Update the old default appearance while preserving customized settings.
        if loaded.appearance.fontSize == 18 && loaded.appearance.cornerRadius == 12 &&
            loaded.appearance.padding == 10 && loaded.appearance.spacing == 8 {
            loaded.appearance.fontSize = 16; loaded.appearance.cornerRadius = 8
            loaded.appearance.padding = 4; loaded.appearance.spacing = 2
        }
        if loaded.voiceModifiers != 0 {
            loaded.voiceKeyCode = 61; loaded.voiceModifiers = 0; loaded.voiceKeyName = nil
        }
        value = loaded
        if let data = try? JSONEncoder().encode(loaded) { UserDefaults.standard.set(data, forKey: "settings.v1") }
    }
    func matchesVoice(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == value.voiceKeyCode &&
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

extension Notification.Name {
    static let voiceTextSettingsChanged = Notification.Name("VoiceTextSettingsChanged")
    static let voiceTextHistoryChanged = Notification.Name("VoiceTextHistoryChanged")
}
