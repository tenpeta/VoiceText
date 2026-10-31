import Foundation

/// IMK clients may support reading the caret, the document, both, or neither.
enum VoiceInsertionCheck {
    static func confirmed(text: String, original: NSRange, current: NSRange,
                          textAtOriginal: String?, textBeforeCaret: String?) -> Bool {
        guard !text.isEmpty else { return false }
        let originalKnown = original.location != NSNotFound && original.length != NSNotFound
        if originalKnown && textAtOriginal == text { return true }
        if textBeforeCaret == text { return true }
        return originalKnown && current.location != NSNotFound && current.length == 0 &&
            current.location == original.location + text.utf16.count
    }
}
