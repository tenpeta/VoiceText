import AppKit
import InputMethodKit
import Carbon

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let settings = AppSettings()
    let engine = RimeEngine()
    let candidates = CandidatePanel()
    let history = HistoryStore(url: AppPaths.support.appendingPathComponent("history.sqlite"))
    lazy var voice = VoiceCoordinator(settings: settings, history: history)
    weak var activeController: InputController?
    var asciiMode = false
    private var settingsWindow: SettingsWindowController?
    private lazy var voicePanel = VoicePanel(voice: voice)
    private var observers: [NSObjectProtocol] = []

    func start() {
        do { try AppPaths.prepare() }
        catch { showError(error) }
        voice.insertText = { [weak self] text in await self?.activeController?.insertVoice(text) ?? false }
        voice.didChange = { [weak self] in self?.updateVoicePanel() }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let selected = InputInstaller.isSelected
                if !selected { self.activeController?.deactivateServer(nil); self.candidates.hide() }
                self.voice.inputSourceDidChange(selected: selected)
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.activeController?.belongsToFrontmostApplication() == false { self.activeController?.deactivateServer(nil) }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.voice.busy == true { self?.voice.cancel() } }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.voice.busy == true { self?.voice.cancel() } }
        })
        engine.prepare()
    }
    func showSettings() {
        activeController?.finishComposition(); candidates.hide()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, voice: voice, engine: engine)
            settingsWindow?.onClose = { [weak self] in
                self?.settingsWindow = nil; NSApp.setActivationPolicy(.accessory)
            }
        }
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil); settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    private func updateVoicePanel() { voicePanel.refreshStatus() }
    func shutdown() { if voice.busy { voice.cancel() }; activeController?.deactivateServer(nil); engine.shutdown() }
    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "VoiceText"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    @objc func openPreferences() { AppRuntime.shared.showSettings() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared.start()
        if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--voice-test") || Bundle.main.bundleURL.standardizedFileURL != InputInstaller.destination.standardizedFileURL {
            AppRuntime.shared.showSettings()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { AppRuntime.shared.showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { AppRuntime.shared.shutdown() }
}
