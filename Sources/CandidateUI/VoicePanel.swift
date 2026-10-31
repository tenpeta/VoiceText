import AppKit

@MainActor
final class VoicePanel: NSPanel {
    private weak var voice: VoiceCoordinator?
    private var displayedText = ""
    private let statusLabel = NSTextField(labelWithString: "")
    private let recordingDot = NSView()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let dismissButton = NSButton(title: "关闭", target: nil, action: nil)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(voice: VoiceCoordinator) {
        self.voice = voice
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating; isOpaque = false; backgroundColor = .clear; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let background = VoicePanelBackground()
        background.wantsLayer = true; background.layer?.masksToBounds = true
        contentView = background
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .center
        background.addSubview(statusLabel)
        recordingDot.wantsLayer = true
        recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordingDot.layer?.cornerRadius = 3
        background.addSubview(recordingDot)

        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        textView.isEditable = false; textView.isSelectable = false
        textView.drawsBackground = false; textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 14)
        textView.alignment = .left; textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        background.addSubview(scrollView)
        for (button, action) in [(copyButton, #selector(copyResult)), (dismissButton, #selector(dismiss))] {
            button.bezelStyle = .rounded; button.target = self; button.action = action
            background.addSubview(button)
        }
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.bezelColor = .systemBlue
        copyButton.contentTintColor = .white
        copyButton.font = .systemFont(ofSize: 12, weight: .medium)
        dismissButton.isBordered = false
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.font = .systemFont(ofSize: 12)
    }

    func refreshStatus() {
        guard let voice else { return }
        let recording = voice.phase == .recording
        let showResult = voice.phase == .idle && voice.needsCopy
        let showError = voice.phase == .idle && voice.hasError
        guard recording || showResult || showError else { orderOut(nil); return }

        present(recording: recording, showResult: showResult,
                text: showResult ? voice.lastText : voice.status, seconds: voice.seconds)
    }

    private func present(recording: Bool, showResult: Bool, text: String, seconds: Int) {
        displayedText = showResult ? text : ""
        recordingDot.isHidden = !recording
        statusLabel.isHidden = !recording
        scrollView.isHidden = recording
        copyButton.isHidden = !showResult; dismissButton.isHidden = recording
        ignoresMouseEvents = recording
        let size: NSSize
        if recording {
            size = NSSize(width: 160, height: 40)
            statusLabel.stringValue = "录音中 · \(seconds) 秒"
            statusLabel.frame = NSRect(x: 29, y: 11, width: 112, height: 18)
            recordingDot.frame = NSRect(x: 19, y: 17, width: 6, height: 6)
        } else {
            let font = NSFont.systemFont(ofSize: 14)
            let naturalWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let width = min(400, max(224, ceil(naturalWidth) + 48))
            let textWidth = width - 48
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.alignment = .left
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
            ]))
            textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: 1)
            textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
            if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
            let textHeight = ceil(textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 18)
            let visibleHeight = min(220, max(18, textHeight))
            size = NSSize(width: width, height: visibleHeight + 88)
            textView.setFrameSize(NSSize(width: textWidth, height: max(textHeight, visibleHeight)))
            scrollView.frame = NSRect(x: 24, y: 64, width: textWidth, height: visibleHeight)
            scrollView.hasVerticalScroller = textHeight > visibleHeight
            textView.scrollToBeginningOfDocument(nil)
            let buttonWidth: CGFloat = 80
            let groupWidth: CGFloat = showResult ? buttonWidth * 2 + 8 : buttonWidth
            let start = (width - groupWidth) / 2
            copyButton.frame = NSRect(x: start, y: 18, width: buttonWidth, height: 30)
            dismissButton.frame = NSRect(x: showResult ? start + buttonWidth + 8 : start,
                                         y: 18, width: buttonWidth, height: 30)
        }
        contentView?.layer?.cornerRadius = recording ? size.height / 2 : 18
        let point = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + 24,
                        width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }
    @objc private func copyResult() {
        let text = displayedText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    @objc private func dismiss() { orderOut(nil) }
}

private final class VoicePanelBackground: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    override var allowsVibrancy: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The material is a background sibling, never an ancestor of text or buttons.
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        // Final appearance: 90% blur blend with an 80% opaque tint.
        blur.alphaValue = 0.9
        for view in [blur, tint] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        tint.wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tint.layer?.backgroundColor = NSColor(calibratedWhite: dark ? 0.14 : 0.98, alpha: 0.8).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: dark ? 1 : 0, alpha: 0.08).cgColor
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
