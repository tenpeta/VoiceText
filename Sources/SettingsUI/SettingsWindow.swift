import AppKit
import SwiftUI
import AVFoundation

private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        let isMouseDown = event.type == .leftMouseDown || event.type == .rightMouseDown
        if isMouseDown, event.window === self, let editingView = activeEditingView {
            let point = editingView.convert(event.locationInWindow, from: nil)
            if !editingView.visibleRect.contains(point) {
                makeFirstResponder(nil)
            }
        }

        super.sendEvent(event)

        if event.type == .leftMouseUp, event.window === self, activeEditor == nil,
           (firstResponder as? ShortcutRecorderButton)?.listening != true {
            makeFirstResponder(nil)
        }
    }

    private var activeEditingView: NSView? {
        if let recorder = firstResponder as? ShortcutRecorderButton, recorder.listening {
            return recorder
        }
        guard let editor = activeEditor else { return nil }
        return editor.isFieldEditor ? (editor.delegate as? NSView ?? editor) : editor
    }

    private var activeEditor: NSTextView? {
        guard let editor = firstResponder as? NSTextView, editor.isEditable else { return nil }
        return editor
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(settings: AppSettings, voice: VoiceCoordinator, engine: RimeEngine) {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
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
                    Text("VoiceText").font(.system(size: 16, weight: .semibold))
                }.padding(.top, 20).padding(.horizontal, 18)
                List(SettingsPage.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.icon).padding(.vertical, 5).tag(item) }
                    .listStyle(.sidebar)
                Text("原生输入 · 云端识别").font(.caption).foregroundStyle(.tertiary).padding(20)
            }.frame(width: 190).background(.quaternary.opacity(0.25))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((page ?? .input).rawValue).font(.system(size: 27, weight: .semibold))
                    .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)
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
            Section {
                if !engine.ready {
                    LabeledContent("全拼", value: engine.error ?? "正在准备词库…")
                }
                LabeledContent("简繁切换") {
                    HStack(spacing: 0) {
                        scriptButton("简体", simplified: true)
                        scriptButton("繁体", simplified: false)
                    }
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("简繁切换")
                }
                Toggle("使用英文标点", isOn: $settings.value.asciiPunctuation)
                Button("打开用户词典目录") { NSWorkspace.shared.open(AppPaths.rime) }
            }
            Section("快捷键") {
                LabeledContent("开始 / 结束语音") {
                    ShortcutRecorder(settings: settings).frame(width: 170, height: 28)
                }
                LabeledContent("切换中英文", value: "Shift ⇧（左 / 右均可）")
                Text("按 Esc 取消设置或录音。").font(.caption).foregroundStyle(.secondary)
            }
            Section("启用输入法") {
                Text("注册后，在系统键盘设置中添加 VoiceText。").font(.callout)
                HStack {
                    Button("注册输入法") { do { try InputInstaller.install(); message = "" } catch { message = error.localizedDescription } }
                    Button("打开键盘设置") { InputInstaller.openSystemSettings() }
                }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
    }

    private func scriptButton(_ title: String, simplified: Bool) -> some View {
        let selected = settings.value.simplified == simplified
        return Button {
            settings.value.simplified = simplified
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 50, height: 24)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 95.0 / 255, green: 83.0 / 255, blue: 239.0 / 255))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: AppSettings

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.focusRingType = .none
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
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
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
        window?.makeFirstResponder(nil)
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
                ScrollView(.horizontal) {
                    CandidatePreview(style: settings.value.appearance).fixedSize()
                }.fixedSize(horizontal: false, vertical: true)
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

private struct SpeechVocabularySettings: View {
    @Binding var text: String
    let provider: ASRProvider
    @State private var newWord = ""
    @State private var reorder: ReorderPreview?

    private struct ReorderPreview {
        let word: String
        let origin: CGRect
        var entries: [String]
        var translation: CGSize = .zero
    }
    @State private var tagFrames: [String: CGRect] = [:]
    @GestureState private var draggedWord: String?
    @State private var editor: Editor?
    @State private var draft = ""

    private enum Editor: Identifiable {
        case edit(String), bulk
        var id: String {
            switch self {
            case .edit(let word): return "edit-\(word)"
            case .bulk: return "bulk"
            }
        }
    }

    var body: some View {
        let entries = SpeechHotwords.entries(in: text)
        let active = Set(SpeechHotwords(text, provider: provider).words)
        Section("热词") {
            HStack {
                Text("输入词或短语")
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                TextField("", text: $newWord)
                    .accessibilityLabel("输入词或短语")
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focusEffectDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                            .allowsHitTesting(false)
                    }
                    .frame(width: 140)
                    .onSubmit(addWord)
                Button("添加", action: addWord)
                    .disabled(SpeechHotwords.entries(in: newWord).isEmpty)
                Button("批量添加…") {
                    draft = ""
                    editor = .bulk
                }
            }
            if !entries.isEmpty {
                VocabularyTagLayout {
                    ForEach(reorder?.entries ?? entries, id: \.self) { word in
                        tag(word, active: active.contains(word))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if let reorder {
                        tagContent(reorder.word, active: active.contains(reorder.word))
                            .frame(width: reorder.origin.width, height: reorder.origin.height)
                            .offset(x: reorder.origin.minX + reorder.translation.width,
                                    y: reorder.origin.minY + reorder.translation.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .coordinateSpace(name: "VocabularyTags")
            }
            Text("添加易误识别的词语或专有名词。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if active.count < entries.count {
                Text("带提示图标的热词会保留在本机，当前服务商会跳过。\(providerLimits)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: draggedWord) {
            if draggedWord == nil { reorder = nil }
        }
        .sheet(item: $editor) { mode in
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .edit:
                    Text("编辑词条").font(.headline)
                    TextField("词或短语", text: $draft)
                        .autocorrectionDisabled()
                case .bulk:
                    Text("批量添加词条").font(.headline)
                    Text("每行粘贴一个词或短语。").foregroundStyle(.secondary)
                    TextEditor(text: $draft)
                        .autocorrectionDisabled()
                        .accessibilityLabel("待添加的词条")
                        .frame(height: 150)
                }
                HStack {
                    Spacer()
                    Button("取消") { editor = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(sheetActionTitle(mode)) { saveDraft(mode) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(SpeechHotwords.entries(in: draft).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private var providerLimits: String {
        let limit = "最多发送 \(SpeechHotwords.limit) 个词条。"
        switch provider {
        case .doubao: return limit
        case .qwen: return limit + "英文短语最多 7 个单词，含中文等非 ASCII 字符时最多 15 个字符。"
        case .tencent: return limit + "腾讯云要求每条最多 30 个字符（最多 10 个汉字），且不能含空格、英文逗号或竖线。"
        }
    }

    private func tag(_ word: String, active: Bool) -> some View {
        tagContent(word, active: active)
            .contentShape(Rectangle())
            .opacity(reorder?.word == word ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named("VocabularyTags"))
            } action: { frame in
                tagFrames[word] = frame
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("VocabularyTags"))
                    .updating($draggedWord) { _, current, _ in current = word }
                    .onChanged { drag in updateReorder(word, drag: drag) }
                    .onEnded { drag in
                        updateReorder(word, drag: drag)
                        if let reorder {
                            text = reorder.entries.joined(separator: "\n")
                        }
                        reorder = nil
                    }
            )
    }

    private func tagContent(_ word: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if !active {
                    Image(systemName: "exclamationmark.circle")
                }
                Text(word).multilineTextAlignment(.leading)
            }
            .foregroundStyle(active ? .primary : .secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                draft = word
                editor = .edit(word)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                draft = word
                editor = .edit(word)
            }
            .help(active ? "编辑 \(word)" : "当前服务商会跳过此词条。\(providerLimits)")
            .accessibilityLabel("编辑 \(word)")
            .accessibilityHint(active ? "" : "当前服务商会跳过此词条")

            Button {
                text = SpeechHotwords.entries(in: text).filter { $0 != word }.joined(separator: "\n")
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .help("删除 \(word)")
            .accessibilityLabel("删除 \(word)")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func updateReorder(_ word: String, drag: DragGesture.Value) {
        guard let origin = tagFrames[word] else { return }
        var preview = reorder ?? ReorderPreview(word: word, origin: origin,
                                                entries: SpeechHotwords.entries(in: text))
        preview.translation = drag.translation
        guard let source = preview.entries.firstIndex(of: word),
              let target = preview.entries.indices.first(where: { index in
                  guard index != source, let frame = tagFrames[preview.entries[index]],
                        frame.insetBy(dx: -3, dy: -3).contains(drag.location) else { return false }
                  return index < source ? drag.location.x <= frame.midX : drag.location.x >= frame.midX
              }) else {
            reorder = preview
            return
        }
        preview.entries.remove(at: source)
        preview.entries.insert(word, at: target)
        withAnimation(.easeInOut(duration: 0.15)) {
            reorder = preview
        }
    }

    private func addWord() {
        append(SpeechHotwords.entries(in: newWord))
        newWord = ""
    }

    private func append(_ entries: [String]) {
        guard !entries.isEmpty else { return }
        text = SpeechHotwords.entries(in: ([text] + entries).joined(separator: "\n")).joined(separator: "\n")
    }

    private func sheetActionTitle(_ mode: Editor) -> String {
        switch mode {
        case .edit: return "保存"
        case .bulk: return "添加"
        }
    }

    private func saveDraft(_ mode: Editor) {
        let entries = SpeechHotwords.entries(in: draft)
        switch mode {
        case .edit(let word):
            guard let replacement = entries.first else { return }
            let updated = SpeechHotwords.entries(in: text).map { $0 == word ? replacement : $0 }
            text = SpeechHotwords.entries(in: updated.joined(separator: "\n")).joined(separator: "\n")
        case .bulk:
            append(entries)
        }
        editor = nil
    }
}

private struct VocabularyTagLayout: Layout {
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(width: proposal.width ?? bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width <= width
                ? ideal
                : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}

private struct VoiceSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: VoiceCoordinator
    @State private var asrKey = ""
    @State private var cleanupKey = ""
    @State private var testingConnection = false
    @State private var connectionPassed = false
    @State private var connectionError: String?
    @State private var message = ""
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    var body: some View {
        Form {
            Section("语音识别") {
                Picker("服务商", selection: $settings.value.provider) { ForEach(ASRProvider.allCases) { Text($0.title).tag($0) } }.disabled(voice.busy || testingConnection)
                LabeledContent("模型名称", value: settings.value.provider.modelTitle)
                LabeledContent("模型 ID", value: settings.value.provider.modelID)
                switch settings.value.provider {
                case .qwen:
                    LabeledContent("地域", value: "华北2（北京）")
                    TextField("业务空间 ID", text: Binding(get: { settings.value.qwenWorkspaceID ?? "" }, set: { settings.value.qwenWorkspaceID = $0 }))
                case .tencent:
                    TextField("AppID", text: Binding(get: { settings.value.tencentAppID ?? "" }, set: { settings.value.tencentAppID = $0 }))
                    TextField("SecretId", text: Binding(get: { settings.value.tencentSecretID ?? "" }, set: { settings.value.tencentSecretID = $0 }))
                case .doubao:
                    Picker("控制台鉴权", selection: Binding(get: { settings.value.doubaoLegacyAuth ?? false }, set: { settings.value.doubaoLegacyAuth = $0 })) {
                        Text("新版控制台").tag(false)
                        Text("旧版控制台").tag(true)
                    }
                    if settings.value.doubaoLegacyAuth == true {
                        TextField("App ID", text: Binding(get: { settings.value.doubaoAppID ?? "" }, set: { settings.value.doubaoAppID = $0 }))
                    }
                }
                SecureField(asrKeyLabel, text: $asrKey)
                if settings.value.provider == .qwen {
                    Toggle("文本润色", isOn: Binding(get: { settings.value.qwenPolish ?? false },
                                                   set: { settings.value.qwenPolish = $0 }))
                } else if settings.value.provider == .doubao {
                    Toggle("语义顺滑", isOn: Binding(get: { settings.value.doubaoPolish ?? false },
                                                   set: { settings.value.doubaoPolish = $0 }))
                }
                HStack {
                    Button("保存密钥") {
                        resetConnectionResult()
                        save(asrKey, account: asrAccount)
                    }
                    .disabled(testingConnection)
                    Button(testingConnection ? "连接中…" : "测试连接") { testConnection() }
                        .disabled(voice.busy || testingConnection)
                    if connectionPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.secondary)
                            .help("连接测试通过")
                            .accessibilityLabel("连接测试通过")
                    }
                }
                if let connectionError {
                    Text(connectionError).font(.caption).foregroundStyle(.secondary)
                }
                if settings.value.provider == .doubao {
                    Text("使用小时版，按语音时长计费。").font(.caption).foregroundStyle(.secondary)
                }
            }
            SpeechVocabularySettings(text: Binding(get: { settings.value.speechHotwords ?? "" },
                                                   set: { settings.value.speechHotwords = $0 }),
                                     provider: settings.value.provider)
            Section("麦克风与录音测试") {
                HStack {
                    Label(permission == .authorized ? "麦克风已授权" : "需要麦克风授权", systemImage: permission == .authorized ? "checkmark.circle.fill" : "mic")
                    Spacer()
                    Button("启用麦克风") { Task { _ = await AVCaptureDevice.requestAccess(for: .audio); permission = AVCaptureDevice.authorizationStatus(for: .audio); if permission == .denied { message = "请在系统设置 → 隐私与安全性 → 麦克风中允许 VoiceText。" } } }
                }
                HStack {
                    Button(voice.phase == .recording ? "结束录音" : "测试录音") { voice.toggle(testRecording: true) }.disabled(testingConnection || (voice.busy && voice.phase != .recording))
                    if voice.canCancel { Button("取消") { voice.cancel() } }
                    if voice.busy { ProgressView().controlSize(.small) }
                    if voice.showsStatusInSettings && !voice.status.isEmpty { Text(voice.status).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("文本整理") {
                Toggle("识别后整理标点和口误", isOn: $settings.value.cleanupEnabled)
                if settings.value.cleanupEnabled {
                    TextField("文本整理接口完整地址", text: $settings.value.cleanup.endpoint)
                    TextField("文本模型名称", text: $settings.value.cleanup.model)
                    SecureField("文本整理 API Key", text: $cleanupKey)
                    Button("保存整理密钥") { save(cleanupKey, account: "cleanup") }
                    Text("整理失败时使用原始转写。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permission = AVCaptureDevice.authorizationStatus(for: .audio)
            }
            .onChange(of: connectionInputs) { resetConnectionResult() }
            .onChange(of: asrAccount, initial: true) {
                asrKey = ""
                do { asrKey = try CredentialStore.shared.read(asrAccount) }
                catch { message = error.localizedDescription }
            }
            .onAppear {
                do { cleanupKey = try CredentialStore.shared.read("cleanup") }
                catch { message = error.localizedDescription }
            }
    }

    private var asrAccount: String { settings.value.asrAccount }

    private var connectionInputs: [String] {
        let value = settings.value
        switch value.provider {
        case .doubao: return [asrAccount, value.doubaoAppID ?? "", String(value.doubaoPolish ?? false), asrKey]
        case .qwen: return [asrAccount, value.qwenWorkspaceID ?? "", String(value.qwenPolish ?? false), asrKey]
        case .tencent: return [asrAccount, value.tencentAppID ?? "", value.tencentSecretID ?? "", asrKey]
        }
    }

    private func resetConnectionResult() {
        connectionPassed = false
        connectionError = nil
    }

    private var asrKeyLabel: String {
        switch settings.value.provider {
        case .doubao: return settings.value.doubaoLegacyAuth == true ? "Access Token" : "API Key"
        case .qwen: return "API Key"
        case .tencent: return "SecretKey"
        }
    }

    private func testConnection() {
        let configuration = settings.value
        let testedInputs = connectionInputs
        testingConnection = true
        resetConnectionResult()
        Task { @MainActor in
            defer { testingConnection = false }
            var sink: VoiceAudioSink?
            do {
                let key = try CredentialStore.shared.read(configuration.asrAccount)
                guard !key.isEmpty else { throw VoiceTextError.message("请先填写并保存密钥，再测试连接。") }
                let service = try configuration.asrConfiguration()
                let connection = VoiceAudioSink(settings: configuration, configuration: service, key: key)
                sink = connection
                try await connection.start()
                if testedInputs == connectionInputs { connectionPassed = true }
            } catch {
                if testedInputs == connectionInputs { connectionError = error.localizedDescription }
            }
            await sink?.cancel()
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
