import AppKit
import InputMethodKit

@MainActor
@objc(VoiceTextInputController)
final class InputController: IMKInputController {
    private var shortcutTracker = SingleKeyShortcutTracker()
    private var session: RimeSession?
    private weak var textClient: IMKTextInput?
    private var preedit = ""
    private var active = false
    private var candidateStart = 0
    private var expandedOffset = 0
    private var currentSnapshot: EngineSnapshot?
    private let replacement = NSRange(location: NSNotFound, length: 0)

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
        textClient = client as? IMKTextInput
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: .voiceTextSettingsChanged, object: nil)
    }
    override func activateServer(_ sender: Any!) {
        shortcutTracker.reset()
        active = true; textClient = sender as? IMKTextInput
        AppRuntime.shared.activeController = self
        ensureSession(); applyOptions()
    }
    override func deactivateServer(_ sender: Any!) {
        shortcutTracker.reset()
        finishComposition()
        active = false; currentSnapshot = nil; candidateStart = 0
        AppRuntime.shared.candidates.hide(for: self)
        if AppRuntime.shared.activeController === self { AppRuntime.shared.activeController = nil }
        textClient = nil; session?.close(); session = nil
    }
    override func inputControllerWillClose() { deactivateServer(nil) }
    override func hidePalettes() { AppRuntime.shared.candidates.hide(for: self) }
    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue) }
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        let interval = Performance.input.beginInterval("HandleKey")
        defer { Performance.input.endInterval("HandleKey", interval) }
        guard let event, event.type == .keyDown || event.type == .flagsChanged else { return false }
        textClient = sender as? IMKTextInput; active = true
        let runtime = AppRuntime.shared
        runtime.activeController = self
        if event.type == .flagsChanged {
            if let key = shortcutTracker.releasedKey(for: event) {
                if key == runtime.settings.value.voiceKeyCode { runtime.voice.toggle() }
                else if key == 56 || key == 60 { toggleLanguage() }
            }
            return false
        }
        shortcutTracker.reset()
        if runtime.settings.matchesVoice(event) {
            if !event.isARepeat { runtime.voice.toggle() }; return true
        }
        if event.keyCode == 53, runtime.voice.busy { runtime.voice.cancel(); return true }
        if event.modifierFlags.contains(.command) { return false }
        ensureSession()
        guard let session else { return false }
        if let snapshot = currentSnapshot, !snapshot.candidates.isEmpty,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            let panel = runtime.candidates
            if event.keyCode == 125 && !panel.isExpanded && runtime.settings.value.appearance.layout == .horizontal {
                toggleCandidates(); return true
            }
            if panel.isExpanded {
                if event.keyCode == 53 { toggleCandidates(); return true }
                if [UInt16(123), 124, 125, 126].contains(event.keyCode) {
                    if !panel.moveSelection(event.keyCode) {
                        if event.keyCode == 126 && candidateStart == 0 && expandedOffset == 0 { toggleCandidates() }
                        else if event.keyCode == 125 { changePage(false) }
                        else if event.keyCode == 126 { changePage(true) }
                    }
                    return true
                }
                if event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 {
                    choose(panel.highlightedIndex); return true
                }
            }
            let range = panel.isExpanded ? panel.numberedRange : panel.visibleRange
            if event.keyCode == 116 || event.charactersIgnoringModifiers == "-" { changePage(true); return true }
            if event.keyCode == 121 || event.charactersIgnoringModifiers == "=" { changePage(false); return true }
            if let character = event.charactersIgnoringModifiers, let number = Int(character), (1...9).contains(number) {
                if number <= range.count { choose(range.lowerBound + number - 1) }
                return true
            }
            if event.keyCode == 49 && range.lowerBound > 0 {
                choose(range.contains(snapshot.highlighted) ? snapshot.highlighted : range.lowerBound); return true
            }
        }
        if runtime.candidates.isExpanded {
            runtime.candidates.setExpanded(false); candidateStart = 0; expandedOffset = 0
        }
        guard let key = Self.rimeKey(event) else { return false }
        var modifiers: Int32 = 0
        if event.modifierFlags.contains(.shift) { modifiers |= 1 }
        if event.modifierFlags.contains(.capsLock) { modifiers |= 2 }
        if event.modifierFlags.contains(.control) { modifiers |= 4 }
        if event.modifierFlags.contains(.option) { modifiers |= 8 }
        let consumed = session.process(key: key, modifiers: modifiers)
        refresh()
        return consumed
    }
    override func commitComposition(_ sender: Any!) { finishComposition() }
    override func cancelComposition() { session?.clear(); setPreedit("", caret: 0); hidePalettes() }

    private func ensureSession() {
        guard session == nil else { return }
        session = AppRuntime.shared.engine.makeSession(); applyOptions()
    }
    private func applyOptions() {
        let runtime = AppRuntime.shared
        session?.set("simplification", runtime.settings.value.simplified)
        session?.set("ascii_punct", runtime.settings.value.asciiPunctuation)
        session?.set("ascii_mode", runtime.asciiMode)
        session?.set("_linear", runtime.settings.value.appearance.layout == .horizontal)
    }
    @objc private func settingsDidChange() { applyOptions(); refresh() }
    func choose(_ index: Int) {
        guard active, let session else { return }
        let panel = AppRuntime.shared.candidates
        let selected = panel.isExpanded ? session.selectGlobal(expandedOffset + index) : session.select(index)
        guard selected else { return }
        panel.setExpanded(false); candidateStart = 0; expandedOffset = 0
        refresh()
    }
    func toggleCandidates() {
        let panel = AppRuntime.shared.candidates
        panel.setExpanded(!panel.isExpanded)
        candidateStart = 0; expandedOffset = 0
        refresh(preservePage: true)
    }
    func changePage(_ backward: Bool) {
        guard active, let snapshot = currentSnapshot else { return }
        let panel = AppRuntime.shared.candidates
        let range = panel.visibleRange
        if backward && range.lowerBound > 0 { candidateStart = panel.previousStart }
        else if !backward && range.upperBound < snapshot.candidates.count { candidateStart = range.upperBound }
        else {
            guard backward ? snapshot.page > 0 : !snapshot.lastPage else { return }
            if panel.isExpanded {
                expandedOffset = max(0, expandedOffset + (backward ? -36 : 36))
            } else { session?.page(backward: backward) }
            candidateStart = backward ? Int.max : 0
        }
        refresh(preservePage: true)
    }

    func finishComposition() {
        guard let session else { return }
        let raw = session.rawInput
        session.finish()
        if let text = session.takeCommit() { commit(text) }
        else if !raw.isEmpty { commit(raw) }
        session.clear(); setPreedit("", caret: 0); hidePalettes()
    }
    func insertVoice(_ text: String) async -> Bool {
        let interval = Performance.voice.beginInterval("VoiceCommit")
        defer { Performance.voice.endInterval("VoiceCommit", interval) }
        guard active, let textClient,
              textClient.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              textClient.bundleIdentifier() != Bundle.main.bundleIdentifier,
              InputInstaller.isSelected else { return false }
        finishComposition()
        let selection = textClient.selectedRange()
        textClient.insertText(text, replacementRange: replacement)
        // IMK insertText has no success return value. Verify the text and caret
        // when document access is supported; otherwise offer the copy fallback.
        guard selection.location != NSNotFound, selection.length != NSNotFound else { return false }
        do { try await Task.sleep(for: .milliseconds(150)) }
        catch { return false }
        guard active, belongsToFrontmostApplication(), InputInstaller.isSelected else { return false }
        let inserted = NSRange(location: selection.location, length: text.utf16.count)
        let caret = textClient.selectedRange()
        return caret.location == NSMaxRange(inserted) && caret.length == 0 &&
            textClient.attributedSubstring(from: inserted)?.string == text
    }
    func belongsToFrontmostApplication() -> Bool {
        active && textClient?.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    private func commit(_ text: String) {
        guard !text.isEmpty else { return }
        textClient?.insertText(text, replacementRange: replacement); preedit = ""
    }
    private func setPreedit(_ text: String, caret: Int) {
        guard preedit != text || !text.isEmpty else { return }
        preedit = text
        let marked = NSMutableAttributedString(string: text)
        if marked.length > 0 { marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: marked.length)) }
        textClient?.setMarkedText(marked, selectionRange: NSRange(location: min(caret, marked.length), length: 0), replacementRange: replacement)
    }
    func refreshCandidates() { candidateStart = 0; refresh(preservePage: true) }
    private func refresh(preservePage: Bool = false) {
        guard active, let session else { return }
        if let text = session.takeCommit() { commit(text) }
        guard let snapshot = session.snapshot(expandedStart: AppRuntime.shared.candidates.isExpanded ? expandedOffset : nil) else { currentSnapshot = nil; candidateStart = 0; setPreedit("", caret: 0); hidePalettes(); return }
        if !preservePage {
            if currentSnapshot?.preedit != snapshot.preedit || currentSnapshot?.page != snapshot.page { candidateStart = 0 }
            else if currentSnapshot?.highlighted != snapshot.highlighted { candidateStart = snapshot.highlighted }
        }
        currentSnapshot = snapshot
        setPreedit(snapshot.preedit, caret: snapshot.caret)
        guard !snapshot.candidates.isEmpty, let textClient else { hidePalettes(); return }
        var anchor = NSRect.zero
        _ = textClient.attributes(forCharacterIndex: 0, lineHeightRectangle: &anchor)
        AppRuntime.shared.candidates.show(snapshot, owner: self, anchor: anchor,
                                         clientLevel: Int(textClient.windowLevel()), style: AppRuntime.shared.settings.value.appearance, start: candidateStart)
    }
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        for (title, action) in [("VoiceText 设置与历史…", #selector(openSettings)),
                                ("切换中英文", #selector(toggleLanguage)),
                                ("切换简繁", #selector(toggleSimplified)),
                                ("开始 / 结束语音", #selector(toggleVoice))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func openSettings() { AppRuntime.shared.showSettings() }
    @objc private func toggleVoice() { AppRuntime.shared.voice.toggle() }
    @objc private func toggleSimplified() { finishComposition(); AppRuntime.shared.settings.value.simplified.toggle() }
    @objc private func toggleLanguage() {
        if let session {
            // express_editor Return keeps confirmed segments and commits the remaining raw input.
            _ = session.process(key: 0xff0d, modifiers: 0)
            if let text = session.takeCommit() { commit(text) }
            session.clear(); setPreedit("", caret: 0); hidePalettes()
        }
        AppRuntime.shared.asciiMode.toggle(); applyOptions()
    }
    private static func rimeKey(_ event: NSEvent) -> Int32? {
        let special: [UInt16: Int32] = [36: 0xff0d, 76: 0xff0d, 48: 0xff09, 51: 0xff08, 117: 0xffff, 53: 0xff1b,
                                           123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52,
                                           115: 0xff50, 119: 0xff57, 116: 0xff55, 121: 0xff56]
        if let key = special[event.keyCode] { return key }
        guard let character = event.charactersIgnoringModifiers?.unicodeScalars.first, character.isASCII else { return nil }
        // Shift must affect punctuation and case, while Control must not turn letters into control bytes.
        if event.modifierFlags.intersection([.control, .option]).isEmpty,
           let scalar = event.characters?.unicodeScalars.first, scalar.isASCII { return Int32(scalar.value) }
        return Int32(character.value)
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
