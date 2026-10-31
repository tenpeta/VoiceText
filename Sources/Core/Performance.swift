import os

enum Performance {
    static let input = OSSignposter(subsystem: "im.voicetext.inputmethod", category: "Input")
    static let voice = OSSignposter(subsystem: "im.voicetext.inputmethod", category: "Voice")
}
