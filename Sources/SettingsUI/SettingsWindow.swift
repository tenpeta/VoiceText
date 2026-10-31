import AppKit
import SwiftUI
import AVFoundation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(settings: AppSettings, voice: VoiceCoordinator, engine: RimeEngine) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "VoiceText"; window.minSize = NSSize(width: 760, height: 540)
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsRoot(settings: settings, voice: voice, engine: engine))
        super.init(window: window); window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        onClose?()
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case input = "输入", appearance = "外观", voice = "语音", history = "历史"
    var id: String { rawValue }
    var icon: String {
        switch self { case .input: return "keyboard"; case .appearance: return "paintpalette"; case .voice: return "waveform"; case .history: return "clock.arrow.circlepath" }
    }
    var subtitle: String {
        switch self {
        case .input: return "流畅输入，从每一次按键开始。"
        case .appearance: return "让候选窗口更适合你的习惯。"
        case .voice: return "说完，识别，再一次性落字。"
        case .history: return "每一次表达，都可以找回来。"
        }
    }
}

private struct SettingsRoot: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: VoiceCoordinator
    @ObservedObject var engine: RimeEngine
    @State private var page: SettingsPage? = .input
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "character.cursor.ibeam").font(.system(size: 25, weight: .medium)).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 3) { Text("VoiceText").font(.headline); Text("轻盈表达，自在输入").font(.caption2).foregroundStyle(.secondary) }
                }.padding(.top, 20).padding(.horizontal, 18)
                List(SettingsPage.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.icon).padding(.vertical, 5).tag(item) }
                    .listStyle(.sidebar)
                Text("原生输入 · 云端识别\nv0.1.0").font(.caption).foregroundStyle(.tertiary).lineSpacing(5).padding(20)
            }.frame(width: 190).background(.quaternary.opacity(0.25))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text((page ?? .input).rawValue).font(.system(size: 27, weight: .semibold))
                    Text((page ?? .input).subtitle).font(.callout).foregroundStyle(.secondary)
                }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)
                switch page ?? .input {
                case .input: InputSettings(settings: settings, engine: engine)
                case .appearance: AppearanceSettingsView(settings: settings)
                case .voice: VoiceSettings(settings: settings, voice: voice)
                case .history: HistoryView(history: voice.history, lastText: voice.lastText)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.tint(.indigo)
    }
}

private struct InputSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: RimeEngine
    @State private var message = ""
    var body: some View {
        Form {
            Section("输入引擎") {
                LabeledContent("全拼", value: engine.ready ? "librime 1.17.0 · 已就绪" : (engine.error ?? "正在准备词库…"))
                Toggle("默认输出简体中文", isOn: $settings.value.simplified)
                Toggle("使用英文标点", isOn: $settings.value.asciiPunctuation)
                Text("使用基础全拼词库，选词习惯保存在本机。空格与数字选词，方向键移动，= / - 翻页。").font(.caption).foregroundStyle(.secondary)
            }
            Section("快捷键") {
                LabeledContent("开始 / 结束语音") {
                    ShortcutRecorder(settings: settings).frame(width: 220, height: 28)
                }
                LabeledContent("切换中英文", value: "Shift ⇧（左 / 右均可）")
                Text("点击语音快捷键后，单独按下并松开一个键即可保存，支持区分左右 Option、Control 等按键。Shift 用于切换中英文，Esc 取消设置。").font(.caption).foregroundStyle(.secondary)
                Text("快捷键仅在本输入法活动时有效；录音期间 Esc 取消。").font(.caption).foregroundStyle(.secondary)
            }
            Section("安装与启用") {
                Text("安装到当前用户的 Library/Input Methods。注册后请在系统设置 → 键盘 → 输入法中添加 VoiceText。").font(.callout)
                HStack {
                    Button("安装 / 注册 VoiceText") { do { try InputInstaller.install(); message = "已请求系统注册。请在系统设置中添加 VoiceText，再切换并尝试输入以确认可用。" } catch { message = error.localizedDescription } }
                    Button("打开键盘设置") { InputInstaller.openSystemSettings() }
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button("打开用户词典目录") { NSWorkspace.shared.open(AppPaths.rime) }
            }
        }.formStyle(.grouped)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.savedTitle = SingleKeyShortcutTracker.name(for: settings.value.voiceKeyCode)
            ?? settings.value.voiceKeyName ?? "按键 \(settings.value.voiceKeyCode)"
        button.onCapture = { code, name in
            var value = settings.value
            value.voiceKeyCode = code; value.voiceModifiers = 0; value.voiceKeyName = name
            settings.value = value
        }
        if !button.listening { button.title = button.savedTitle + " · 点击设置" }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var savedTitle = ""
    var onCapture: ((UInt16, String) -> Void)?
    private(set) var listening = false
    private var tracker = SingleKeyShortcutTracker()
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        tracker.reset(); listening = true; title = "请按一个键…"
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard listening else { super.keyDown(with: event); return }
        tracker.reset()
        if event.keyCode == 53 { stopRecording(); return }
        guard !event.isARepeat,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            title = "请单独按一个键"; return
        }
        save(event.keyCode, name: SingleKeyShortcutTracker.name(for: event.keyCode)
             ?? event.charactersIgnoringModifiers?.uppercased() ?? "按键 \(event.keyCode)")
    }

    override func flagsChanged(with event: NSEvent) {
        guard listening else { super.flagsChanged(with: event); return }
        if let code = tracker.releasedKey(for: event) {
            guard code != 56 && code != 60 else { title = "Shift 已用于切换中英文"; return }
            save(code, name: SingleKeyShortcutTracker.name(for: code) ?? "按键 \(code)")
        }
    }

    private func save(_ code: UInt16, name: String) {
        listening = false; tracker.reset()
        savedTitle = name; title = name + " · 点击设置"
        onCapture?(code, name)
    }

    private func stopRecording() {
        listening = false; tracker.reset(); title = savedTitle + " · 点击设置"
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Section("主题与文字") {
                    Picker("主题", selection: $settings.value.appearance.theme) { Text("跟随系统").tag(ThemeMode.system); Text("浅色").tag(ThemeMode.light); Text("深色").tag(ThemeMode.dark) }
                    Picker("候选布局", selection: $settings.value.appearance.layout) { Text("横排").tag(CandidateLayout.horizontal); Text("竖排").tag(CandidateLayout.vertical) }
                    Picker("字体", selection: $settings.value.appearance.fontName) {
                        Text("苹方").tag("PingFangSC-Regular"); Text("宋体").tag("SongtiSC-Regular"); Text("系统字体").tag("")
                    }
                    SliderRow(title: "字号", value: $settings.value.appearance.fontSize, range: 13...28)
                }
            Section("实时预览") {
                ScrollView([.horizontal, .vertical]) {
                    CandidatePreview(style: settings.value.appearance).fixedSize()
                }.frame(height: settings.value.appearance.layout == .horizontal ? 72 : 145)
            }
        }.formStyle(.grouped)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View { LabeledContent(title) { Slider(value: $value, in: range, step: 1).frame(maxWidth: 200); Text("\(Int(value))").monospacedDigit().frame(width: 26) } }
}

private struct VoiceSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: VoiceCoordinator
    @State private var asrKey = ""
    @State private var cleanupKey = ""
    @State private var testingConnection = false
    @State private var message = ""
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    var body: some View {
        Form {
            Section("语音识别 · ASR") {
                Picker("服务商", selection: $settings.value.provider) { ForEach(ASRProvider.allCases) { Text($0.title).tag($0) } }.disabled(voice.busy)
                TextField("完整接口地址", text: $settings.value.service.endpoint).textContentType(.URL)
                TextField(settings.value.provider == .doubao ? "资源 ID" : "模型名称", text: $settings.value.service.model)
                if settings.value.provider == .doubao {
                    Picker("控制台鉴权", selection: Binding(get: { settings.value.doubaoLegacyAuth ?? false }, set: { settings.value.doubaoLegacyAuth = $0 })) {
                        Text("新版控制台 API Key").tag(false)
                        Text("旧版控制台 App ID / Access Token").tag(true)
                    }
                    if settings.value.doubaoLegacyAuth == true {
                        TextField("App ID", text: Binding(get: { settings.value.doubaoAppID ?? "" }, set: { settings.value.doubaoAppID = $0 }))
                    }
                }
                SecureField(settings.value.provider == .doubao && settings.value.doubaoLegacyAuth == true ? "Access Token" : "ASR API Key", text: $asrKey)
                HStack {
                    Button("保存 ASR 密钥") { save(asrKey, account: asrAccount) }
                    Button("恢复接口预设") { settings.value.service = .preset(settings.value.provider) }
                    if settings.value.provider == .doubao {
                        Button(testingConnection ? "连接中…" : "测试连接") { testConnection() }
                            .disabled(voice.busy || testingConnection)
                    }
                }
                Text(settings.value.provider == .doubao ? "使用豆包流式语音识别 2.0 的一句话接口。根据控制台版本选择鉴权方式，资源 ID 按已开通的小时版或并发版填写。" : "录音结束后调用专用 ASR 模型，等待完整结果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("麦克风与录音测试") {
                HStack {
                    Label(permission == .authorized ? "麦克风已授权" : "需要麦克风授权", systemImage: permission == .authorized ? "checkmark.circle.fill" : "mic")
                    Spacer()
                    Button("启用麦克风") { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); permission = AVCaptureDevice.authorizationStatus(for: .audio); if permission == .denied { message = "请在系统设置 → 隐私与安全性 → 麦克风中允许 VoiceText。" } } }
                }
                HStack {
                    Button(voice.phase == .recording ? "结束录音" : "测试录音") { voice.toggle() }.disabled(testingConnection || (voice.busy && voice.phase != .recording))
                    if voice.busy { Button("取消") { voice.cancel() }; ProgressView().controlSize(.small) }
                    Text(voice.status).font(.caption).foregroundStyle(.secondary)
                }
                Text("最长三分钟。测试结果保存到历史，设置窗口不会接收自动回填。").font(.caption).foregroundStyle(.secondary)
            }
            Section("可选文本整理") {
                Toggle("识别后整理标点、口误和重复", isOn: $settings.value.cleanupEnabled)
                if settings.value.cleanupEnabled {
                    TextField("文本整理接口完整地址", text: $settings.value.cleanup.endpoint)
                    TextField("文本模型名称", text: $settings.value.cleanup.model)
                    SecureField("文本整理 API Key", text: $cleanupKey)
                    Button("保存整理密钥") { save(cleanupKey, account: "cleanup") }
                }
                Text("只发送本次识别文本。整理失败时使用原始转写；关闭后不调用文本模型。").font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text("密钥保存在仅当前账户可读的本地文件中，不使用钥匙串加密。识别文本长期保存在本机历史；音频不长期保存。清空密钥后点击保存可删除凭据。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permission = AVCaptureDevice.authorizationStatus(for: .audio)
            }
            .task(id: asrAccount) {
                do { asrKey = try CredentialStore.shared.read(asrAccount); cleanupKey = try CredentialStore.shared.read("cleanup") }
                catch { message = error.localizedDescription }
            }
    }
    private var asrAccount: String {
        settings.value.provider == .doubao && settings.value.doubaoLegacyAuth == true ? "asr.doubao.legacy" : "asr.\(settings.value.provider.rawValue)"
    }
    private func testConnection() {
        let configuration = settings.value
        let account = asrAccount
        testingConnection = true
        message = "正在测试豆包连接，不会录音…"
        Task { @MainActor in
            defer { testingConnection = false }
            var session: DoubaoSession?
            do {
                let key = try CredentialStore.shared.read(account)
                guard !key.isEmpty else { throw VoiceTextError.message("请先填写并保存 ASR 密钥，再测试连接。") }
                let connection = DoubaoSession(configuration: configuration.service, key: key,
                    appID: configuration.doubaoLegacyAuth == true ? (configuration.doubaoAppID ?? "") : nil)
                session = connection
                try await connection.start()
                message = "豆包 WebSocket 已连接，可以测试录音。"
            } catch { message = error.localizedDescription }
            await session?.cancel()
        }
    }
    private func save(_ value: String, account: String) {
        do { try CredentialStore.shared.save(value.trimmingCharacters(in: .whitespacesAndNewlines), account: account); message = value.isEmpty ? "已删除密钥。" : "已保存到本机。" }
        catch { message = error.localizedDescription }
    }
}

private struct HistoryView: View {
    let history: HistoryStore
    let lastText: String
    @State private var records: [VoiceRecord] = []
    @State private var offset = 0
    @State private var hasNext = false
    @State private var error = ""
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("仅保存文字，不保存录音").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("刷新") { Task { await load() } }
                Button("清空历史", role: .destructive) { confirmClear = true }.disabled(records.isEmpty)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            if records.isEmpty {
                VStack(spacing: 12) { Image(systemName: "text.bubble").font(.system(size: 36)).foregroundStyle(.tertiary); Text("还没有语音记录").font(.headline); Text("在语音页完成一次录音，结果就会保存在这里。").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(record.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    Text(ASRProvider(rawValue: record.provider)?.title ?? record.provider).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("复制") { copy(record.finalText) }.buttonStyle(.borderless)
                                    Button(role: .destructive) { Task { do { try await history.delete(id: record.id); await load() } catch { self.error = error.localizedDescription } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                                }
                                Text(record.finalText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if record.rawText != record.finalText { DisclosureGroup("识别原文") { Text(record.rawText).textSelection(.enabled).foregroundStyle(.secondary) }.font(.caption) }
                            }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            HStack {
                Button("上一页") { offset = max(0, offset - 30) }.disabled(offset == 0)
                Text("第 \(offset / 30 + 1) 页").font(.caption).foregroundStyle(.secondary)
                Button("下一页") { offset += 30 }.disabled(!hasNext)
                Spacer()
                if !lastText.isEmpty { Button("复制最近一次结果") { copy(lastText) } }
            }
        }.padding(.horizontal, 28).padding(.bottom, 24)
            .task(id: offset) { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .voiceTextHistoryChanged)) { _ in Task { await load() } }
            .alert("清空全部语音历史？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { Task { do { try await history.clear(); offset = 0; await load() } catch { self.error = error.localizedDescription } } }
            } message: { Text("这会删除本机保存的识别原文和整理结果。") }
    }
    private func load() async {
        do { let page = try await history.page(offset: offset, limit: 31); hasNext = page.count > 30; records = Array(page.prefix(30)); error = "" }
        catch { self.error = error.localizedDescription }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
