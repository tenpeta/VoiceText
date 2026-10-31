import Foundation
import Combine

struct Candidate: Equatable {
    let text: String
    let comment: String
}
struct EngineSnapshot {
    let preedit: String
    let caret: Int
    let selection: NSRange
    let candidates: [Candidate]
    let highlighted: Int
    let page: Int
    let lastPage: Bool
}

@MainActor
final class RimeEngine: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var error: String?
    private var preparing = false
    private let initialization = DispatchQueue(label: "im.voicetext.rime.initialize", qos: .userInitiated)
    private var sessions: Set<UInt> = []

    func prepare() {
        guard !ready, !preparing else { return }
        preparing = true
        let shared = Bundle.main.resourceURL!.appendingPathComponent("Rime").path
        let user = AppPaths.rime.path, logs = AppPaths.logs.path
        initialization.async {
            let success = vt_rime_start(shared, user, logs) != 0
            // Probe schema loading so an incomplete bundle never reports itself as ready.
            let probe = success ? vt_rime_session() : 0
            if probe != 0 { vt_rime_destroy(probe) }
            DispatchQueue.main.async {
                self.preparing = false
                self.ready = probe != 0
                if !self.ready { self.error = "拼音引擎初始化失败，请检查随包词库后重启输入法。" }
            }
        }
    }
    func makeSession() -> RimeSession? {
        guard ready else { return nil }
        let identifier = vt_rime_session()
        guard identifier != 0 else { return nil }
        sessions.insert(identifier)
        return RimeSession(id: identifier, engine: self)
    }
    fileprivate func destroy(_ id: UInt) {
        if sessions.remove(id) != nil { vt_rime_destroy(id) }
    }
    func shutdown() {
        guard !preparing else { return }
        for id in sessions { vt_rime_destroy(id) }; sessions.removeAll()
        if ready { vt_rime_finalize() }; ready = false
    }
}

@MainActor
final class RimeSession {
    private(set) var id: UInt
    private weak var engine: RimeEngine?
    init(id: UInt, engine: RimeEngine) { self.id = id; self.engine = engine }
    func close() { guard id != 0 else { return }; engine?.destroy(id); id = 0 }
    func process(key: Int32, modifiers: Int32) -> Bool { vt_rime_key(id, key, modifiers) != 0 }
    func select(_ index: Int) -> Bool { index >= 0 && vt_rime_select(id, index) != 0 }
    func selectGlobal(_ index: Int) -> Bool { index >= 0 && vt_rime_select_global(id, index) != 0 }
    func page(backward: Bool) { _ = vt_rime_page(id, backward ? 1 : 0) }
    func set(_ option: String, _ value: Bool) { vt_rime_option(id, option, value ? 1 : 0) }
    func clear() { vt_rime_clear(id) }
    func finish() { _ = vt_rime_commit(id) }
    func takeCommit() -> String? {
        guard let pointer = vt_rime_take_commit(id) else { return nil }
        defer { vt_rime_free_string(pointer) }; return String(cString: pointer)
    }
    var rawInput: String {
        guard let pointer = vt_rime_input(id) else { return "" }
        defer { vt_rime_free_string(pointer) }; return String(cString: pointer)
    }
    func snapshot(expandedStart: Int? = nil) -> EngineSnapshot? {
        var value = VTSnapshot()
        let success = expandedStart.map { vt_rime_expanded_snapshot(id, Int32($0), 36, &value) }
            ?? vt_rime_snapshot(id, &value)
        guard success != 0 else { return nil }
        defer { vt_rime_free_snapshot(&value) }
        let preedit = value.preedit.map { String(cString: $0) } ?? ""
        let start = TextOffsets.utf16Offset(Int(value.selection_start), in: preedit)
        let end = TextOffsets.utf16Offset(Int(value.selection_end), in: preedit)
        let candidates = (0..<Int(value.count)).map { index -> Candidate in
            let item = value.candidates![index]
            return Candidate(text: item.text.map { String(cString: $0) } ?? "", comment: item.comment.map { String(cString: $0) } ?? "")
        }
        return .init(preedit: preedit, caret: TextOffsets.utf16Offset(Int(value.cursor), in: preedit),
                     selection: NSRange(location: start, length: max(0, end - start)), candidates: candidates,
                     highlighted: Int(value.highlighted), page: Int(value.page), lastPage: value.last_page != 0)
    }
    deinit {
        let identifier = id
        let owner = engine
        if identifier != 0 { Task { @MainActor in owner?.destroy(identifier) } }
    }
}
