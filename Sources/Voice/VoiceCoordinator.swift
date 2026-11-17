import AppKit
import AVFoundation

enum VoicePhase: Equatable { case idle, connecting, recording, recognizing, cleaning }

actor VoiceAudioSink {
    private let settings: SettingsValue
    private let configuration: ServiceConfiguration
    private let key: String
    private var doubao: DoubaoSession?
    private var tencent: TencentSession?
    private var file: WAVFile?
    private var samples = 0

    init(settings: SettingsValue, configuration: ServiceConfiguration, key: String) {
        self.settings = settings; self.configuration = configuration; self.key = key
    }

    func start() async throws {
        switch settings.provider {
        case .doubao:
            let appID = settings.doubaoLegacyAuth == true ? (settings.doubaoAppID ?? "") : nil
            let session = DoubaoSession(configuration: configuration, key: key, appID: appID)
            doubao = session; try await session.start()
        case .qwen:
            file = try WAVFile(directory: AppPaths.temporary)
        case .tencent:
            let session = try TencentSession(configuration: configuration, appID: settings.tencentAppID ?? "",
                                             secretID: settings.tencentSecretID ?? "", secretKey: key)
            tencent = session; try await session.start()
        }
    }
    func append(_ pcm: Data) async throws {
        samples += pcm.count / 2
        if let doubao { try await doubao.append(pcm) }
        else if let tencent { try await tencent.append(pcm) }
        else { try file?.append(pcm) }
    }
    func finish() async throws -> ASRResult {
        let interval = Performance.voice.beginInterval("FinalASR")
        defer { Performance.voice.endInterval("FinalASR", interval) }
        guard samples >= 4800 else { throw VoiceTextError.noSpeech }
        if let doubao { return try await doubao.finish() }
        if let tencent { return try await tencent.finish() }
        guard let file else { throw CancellationError() }
        defer { file.remove(); self.file = nil }
        try file.finish()
        return try await HTTPService.recognizeQwen(file: file.url, configuration: configuration, key: key)
    }
    func cancel() async {
        await doubao?.cancel(); doubao = nil
        await tencent?.cancel(); tencent = nil
        file?.remove(); file = nil
    }
}

@MainActor
final class VoiceCoordinator: ObservableObject {
    @Published private(set) var phase: VoicePhase = .idle
    @Published private(set) var status = ""
    private(set) var showsStatusInSettings = true
    @Published private(set) var seconds = 0
    @Published private(set) var lastText = ""
    private(set) var needsCopy = false
    private(set) var hasError = false
    var didChange: (() -> Void)?
    var insertText: ((String) async -> Bool)?
    private let settings: AppSettings
    let history: HistoryStore
    private var capture: AudioCapture?
    private var task: Task<Void, Never>?
    private var pump: Task<ASRResult, Error>?
    private var clock: Task<Void, Never>?
    private var sink: VoiceAudioSink?
    private var generation: UUID?
    private var cancelling = false

    init(settings: AppSettings, history: HistoryStore) { self.settings = settings; self.history = history }
    var busy: Bool { phase != .idle }
    private var savingTestResult = false
    var canCancel: Bool { busy && !cancelling && !savingTestResult }

    func toggle(testRecording: Bool = false) {
        if phase == .recording { stop() }
        else if !busy { start(testRecording: testRecording) }
    }
    func start(testRecording: Bool = false) {
        guard !busy else { return }
        needsCopy = false; hasError = false
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            hasError = true
            update(.idle, "请先在设置的语音页启用麦克风权限。"); return
        }
        let configuration = settings.value
        let key: String
        let service: ServiceConfiguration
        do {
            key = try CredentialStore.shared.read(configuration.asrAccount)
            guard !key.isEmpty else { throw VoiceTextError.message("请先在设置的语音页保存 ASR 密钥。") }
            service = try configuration.asrConfiguration()
        } catch { hasError = true; update(.idle, error.localizedDescription); return }
        let id = UUID(); generation = id; seconds = 0
        let capture = AudioCapture(); self.capture = capture
        update(.connecting, configuration.provider == .qwen ? "正在准备录音…" : "正在连接\(configuration.provider.title)语音识别…")
        task = Task {
            guard self.generation == id, !Task.isCancelled else { return }
            let sink = VoiceAudioSink(settings: configuration, configuration: service, key: key)
            self.sink = sink
            do {
                try await sink.start(); try Task.checkCancellation()
                guard self.generation == id else { throw CancellationError() }
                let audio = try capture.start()
                update(.recording, "正在录音")
                clock = Task {
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(1))
                            guard self.generation == id, self.phase == .recording else { return }
                            self.seconds += 1; self.didChange?()
                            if self.seconds >= 180 { self.stop(); return }
                        }
                    } catch {}
                }
                let pump = Task {
                    for try await packet in audio { try Task.checkCancellation(); try await sink.append(packet) }
                    try Task.checkCancellation()
                    return try await sink.finish()
                }
                self.pump = pump
                let result = try await pump.value
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                lastText = result.text
                var warning: String?
                var recordID: String?
                if !testRecording {
                    do { recordID = try await history.insert(result) }
                    catch { warning = "历史保存失败，当前结果仍可复制。" }
                    NotificationCenter.default.post(name: .voiceTextHistoryChanged, object: nil)
                    try Task.checkCancellation()
                    guard generation == id else { throw CancellationError() }
                }
                if configuration.cleanupEnabled {
                    update(.cleaning, "正在整理文本…")
                    do {
                        let cleanupKey = try CredentialStore.shared.read("cleanup")
                        guard !cleanupKey.isEmpty else { throw VoiceTextError.message("未配置文本整理密钥。") }
                        let cleaned = try await HTTPService.clean(result.text, configuration: configuration.cleanup, key: cleanupKey)
                        try Task.checkCancellation()
                        guard generation == id else { throw CancellationError() }
                        lastText = cleaned
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        guard generation == id else { throw CancellationError() }
                        warning = "整理未完成，已保留识别原文。"; lastText = result.text
                    }
                    if let recordID {
                        do { try await history.update(id: recordID, finalText: lastText) }
                        catch { warning = "整理结果保存失败，当前结果仍可复制。" }
                    }
                }
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                if testRecording {
                    savingTestResult = true
                    update(.recognizing, "正在保存测试结果…")
                    do { _ = try await history.insert(result, finalText: lastText) }
                    catch { warning = "历史保存失败，当前结果仍可复制。" }
                }
                let submitted = testRecording ? false : (await insertText?(lastText) ?? false)
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                needsCopy = !submitted && !lastText.isEmpty
                NotificationCenter.default.post(name: .voiceTextHistoryChanged, object: nil)
                await sink.cancel()
                guard generation == id else { return }
                self.capture = nil; self.sink = nil; self.pump = nil; self.task = nil; self.generation = nil
                savingTestResult = false
                update(.idle, warning ?? "录音已结束", showInSettings: warning != nil)
            } catch {
                await capture.stop(); await sink.cancel()
                guard generation == id else { return }
                clock?.cancel(); clock = nil
                self.capture = nil; self.sink = nil; self.pump = nil; self.task = nil; generation = nil
                if error is CancellationError { update(.idle, "已取消", showInSettings: false) }
                else if (error as? VoiceTextError) == .noSpeech { update(.idle, "录音已结束", showInSettings: false) }
                else { hasError = true; update(.idle, error.localizedDescription) }
            }
        }
    }
    func stop() {
        guard phase == .recording else { return }
        clock?.cancel(); clock = nil
        update(.recognizing, "正在等待最终识别结果…")
        let capture = self.capture
        Task { await capture?.stop() }
    }
    func cancel() {
        guard canCancel else { return }
        cancelling = true
        generation = nil
        task?.cancel(); task = nil; pump?.cancel(); pump = nil
        clock?.cancel(); clock = nil
        let sink = self.sink; self.sink = nil
        let capture = self.capture; self.capture = nil
        // Mark the UI busy until the microphone and old session have actually stopped.
        update(.recognizing, "正在取消…")
        Task {
            await sink?.cancel(); await capture?.stop()
            cancelling = false
            update(.idle, "已取消", showInSettings: false)
        }
    }
    func inputSourceDidChange(selected: Bool) {
        if !selected && (phase == .recording || phase == .connecting) { cancel() }
    }
    private func update(_ phase: VoicePhase, _ text: String, showInSettings: Bool = true) {
        showsStatusInSettings = showInSettings
        self.phase = phase; status = text; didChange?()
    }
}
