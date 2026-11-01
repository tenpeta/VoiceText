import AppKit
import QuartzCore
import SwiftUI

struct CandidatePreview: NSViewRepresentable {
    let style: AppearanceSettings
    private var snapshot: EngineSnapshot {
        .init(preedit: "ni hao", caret: 6, selection: NSRange(location: 0, length: 6),
              candidates: [.init(text: "你好", comment: ""), .init(text: "拟好", comment: ""), .init(text: "你号", comment: "")],
              highlighted: 0, page: 0, lastPage: true)
    }
    func makeNSView(context: Context) -> NSView { CandidateView() }
    func updateNSView(_ view: NSView, context: Context) {
        switch style.theme {
        case .system: view.appearance = nil
        case .light: view.appearance = NSAppearance(named: .aqua)
        case .dark: view.appearance = NSAppearance(named: .darkAqua)
        }
        if let canvas = view as? CandidateView {
            _ = canvas.configure(snapshot, style: style, maxWidth: style.tuning.width)
        }
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        (nsView as? CandidateView)?.configure(snapshot, style: style, maxWidth: style.tuning.width)
    }
}

@MainActor
final class CandidatePanel: NSPanel {
    private let canvas = CandidateView()
    weak var owner: InputController?
    private var lastAnchor: NSRect?
    private var displayedExpanded = false
    var visibleRange: Range<Int> { canvas.visibleRange }
    var previousStart: Int { canvas.previousStart }
    var nextStart: Int { canvas.nextStart }
    var isExpanded: Bool { canvas.expanded }
    var highlightedIndex: Int { canvas.highlightedIndex }
    var numberedRange: Range<Int> { canvas.numberedRange }
    var needsPreviousRow: Bool { canvas.needsPreviousRow }
    func setExpanded(_ expanded: Bool) { canvas.expanded = expanded }
    func moveSelection(_ keyCode: UInt16) -> Bool { canvas.moveSelection(keyCode) }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        contentView = canvas
        canvas.select = { [weak self] index in self?.owner?.choose(index) }
        canvas.toggle = { [weak self] in self?.owner?.toggleCandidates() }
        canvas.page = { [weak self] backward in self?.owner?.changePage(backward) }
    }
    func show(_ snapshot: EngineSnapshot, owner: InputController, anchor: NSRect, clientLevel: Int, style: AppearanceSettings, start: Int) {
        if self.owner !== owner { lastAnchor = nil }
        self.owner = owner
        if anchor.width.isFinite && anchor.height.isFinite && anchor.origin.x.isFinite && anchor.origin.y.isFinite && anchor.height > 0 {
            lastAnchor = anchor
        }
        let point = lastAnchor?.origin ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        hasShadow = style.tuning.shadow
        let size = canvas.configure(snapshot, style: style, maxWidth: min(style.tuning.width, visible.width - 24), start: start)
        var origin: NSPoint
        if let rect = lastAnchor {
            origin = NSPoint(x: rect.minX + style.tuning.offsetX, y: rect.minY - size.height - style.tuning.offsetY)
            if origin.y < visible.minY { origin.y = rect.maxY + style.tuning.offsetY }
        } else { origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80) }
        origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)
        origin.y = min(max(origin.y, visible.minY + 6), visible.maxY - size.height - 6)
        level = NSWindow.Level(rawValue: clientLevel + 1)
        switch style.theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        let targetFrame = NSRect(origin: origin, size: size)
        let animate = isVisible && displayedExpanded != canvas.expanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        displayedExpanded = canvas.expanded
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true)
        }
        orderFrontRegardless()
    }
    func hide(for controller: InputController? = nil) {
        guard controller == nil || owner === controller else { return }
        orderOut(nil); owner = nil; lastAnchor = nil; canvas.expanded = false
    }
}

@MainActor
private final class CandidateView: NSView {
    private let backdrop = NSVisualEffectView()
    private let artwork = CandidateArtwork()
    private let tint = NSView()
    private let scrollThumb = NSView()
    private var scrollHideTask: Task<Void, Never>?
    private var configuredExpanded = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.autoresizingMask = [.width, .height]
        artwork.autoresizingMask = [.width, .height]
        artwork.render = { [weak self] rect in self?.drawCandidates(rect) }
        addSubview(backdrop)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        addSubview(artwork)
        scrollThumb.wantsLayer = true
        scrollThumb.layer?.cornerRadius = 2.5
        scrollThumb.alphaValue = 0
        addSubview(scrollThumb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    var select: ((Int) -> Void)?
    var toggle: (() -> Void)?
    var expanded = false {
        didSet {
            if !expanded {
                configuredExpanded = false
                scrollHideTask?.cancel()
                scrollThumb.layer?.removeAllAnimations()
                scrollThumb.alphaValue = 0
            }
        }
    }
    private(set) var highlightedIndex = 0
    var numberedRange: Range<Int> {
        guard let selected = boxes.indices.first(where: { visibleRange.lowerBound + $0 == highlightedIndex }) else { return visibleRange }
        let row = boxes[selected].minY
        let indices = boxes.indices.filter { boxes[$0].minY == row }
        return (visibleRange.lowerBound + (indices.first ?? 0))..<(visibleRange.lowerBound + (indices.last ?? 0) + 1)
    }
    var needsPreviousRow: Bool {
        expanded && visibleRange.lowerBound > 0 && numberedRange.lowerBound == visibleRange.lowerBound
    }
    private var toggleBox = NSRect.zero
    private var togglePressed = false
    var page: ((Bool) -> Void)?
    private var snapshot: EngineSnapshot?
    private var style = AppearanceSettings()
    private var boxes: [NSRect] = []
    private(set) var visibleRange = 0..<0
    private(set) var previousStart = 0
    private(set) var nextStart = 0
    private var pressed: Int?
    private var lastScroll = Date.distantPast
    private var numberFont: NSFont { .monospacedDigitSystemFont(ofSize: style.tuning.numberSize, weight: .medium) }
    private var font: NSFont { NSFont(name: style.fontName, size: style.fontSize) ?? .systemFont(ofSize: style.fontSize) }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { frame.size }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func configure(_ snapshot: EngineSnapshot, style: AppearanceSettings, maxWidth: CGFloat, start: Int = 0) -> NSSize {
        let oldStart = visibleRange.lowerBound
        let wasExpanded = configuredExpanded
        configuredExpanded = expanded
        let keepSelection = expanded && self.snapshot?.preedit == snapshot.preedit
        if !wasExpanded || !keepSelection {
            scrollHideTask?.cancel()
            scrollThumb.layer?.removeAllAnimations()
            scrollThumb.alphaValue = 0
        }
        self.snapshot = snapshot; self.style = style; pressed = nil
        if !keepSelection { highlightedIndex = snapshot.highlighted }
        let tuning = style.tuning
        let padding = tuning.padding, gap = tuning.spacing
        let wordPadding = max(tuning.wordPadding, style.fontSize * 0.5)
        let numberWidth = tuning.showNumbers ? ceil(("1" as NSString).size(withAttributes: [.font: numberFont]).width) + 4 : 0
        let inset = wordPadding + numberWidth
        let contentWidth = expanded ? maxWidth - 10 : maxWidth - 29
        let height = max(ceil(font.ascender - font.descender) + tuning.rowPadding * 2, style.fontSize * 1.5)
        let widths = snapshot.candidates.map { min(contentWidth - padding * 2, ceil(($0.text as NSString).size(withAttributes: [.font: font]).width) + inset + wordPadding) }
        boxes = []
        var starts = [0]
        if style.layout == .horizontal {
            var used = padding, columns = 0
            for (index, width) in widths.enumerated() {
                if used > padding && (used + width > contentWidth - padding || columns == 9) { starts.append(index); used = padding; columns = 0 }
                used += width + gap; columns += 1
            }
        }
        let first = starts.last(where: { $0 <= start }) ?? 0
        previousStart = starts.last(where: { $0 < first }) ?? 0
        let size: NSSize
        if style.layout == .horizontal && expanded {
            // Lay out one continuous list before choosing the visible rows.
            // Wide phrases span columns; short words share aligned columns.
            let cell = (contentWidth - padding * 2 + gap) / 6
            var allBoxes: [NSRect] = []
            var rowStarts = [0]
            var column = 0
            var row = 0
            for (index, measuredWidth) in widths.enumerated() {
                let span = min(6, max(1, Int(ceil((measuredWidth + gap) / cell))))
                if column + span > 6 {
                    row += 1; column = 0; rowStarts.append(index)
                }
                allBoxes.append(NSRect(x: padding + CGFloat(column) * cell,
                                       y: padding + CGFloat(row) * (height + gap),
                                       width: CGFloat(span) * cell - gap, height: height))
                column += span
            }
            let availableHeight = ((window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 600) - 100
            let maxRows = min(5, max(1, Int(availableHeight / (height + gap))))
            let requestedRow = rowStarts.lastIndex(where: { $0 <= start }) ?? 0
            let firstRow = min(requestedRow, max(0, rowStarts.count - maxRows))
            let endRow = min(rowStarts.count, firstRow + maxRows)
            let begin = rowStarts[firstRow]
            let end = endRow < rowStarts.count ? rowStarts[endRow] : widths.count
            let offset = CGFloat(firstRow) * (height + gap)
            boxes = allBoxes[begin..<end].map { $0.offsetBy(dx: 0, dy: -offset) }
            previousStart = rowStarts[max(0, firstRow - 1)]
            nextStart = firstRow + 1 < rowStarts.count ? rowStarts[firstRow + 1] : begin
            visibleRange = begin..<end
            size = NSSize(width: maxWidth, height: padding * 2 + CGFloat(endRow - firstRow) * (height + gap) - gap)
            let trackHeight = max(0, size.height - 16)
            // The engine loads candidates incrementally, so its loaded count is not a total.
            let thumbHeight = min(trackHeight, 28)
            let progress = CGFloat(firstRow) / CGFloat(max(1, rowStarts.count - maxRows))
            scrollThumb.frame = NSRect(x: maxWidth - 8, y: 8 + (trackHeight - thumbHeight) * progress,
                                       width: 5, height: thumbHeight)
            scrollThumb.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
            if wasExpanded && keepSelection && oldStart != begin {
                showScrollIndicator()
            }
        } else if style.layout == .vertical {
            let width = min(maxWidth - padding * 2, max(120, widths.max() ?? 120))
            for i in first..<widths.count { boxes.append(NSRect(x: padding, y: padding + CGFloat(i - first) * (height + gap), width: width, height: height)) }
            size = NSSize(width: width + padding * 2, height: padding * 2 + CGFloat(boxes.count) * height + CGFloat(max(0, boxes.count - 1)) * gap)
        } else {
            var x = padding, y = padding
            var columns = 0
            let beginning = first
            for measuredWidth in widths.dropFirst(beginning) {
                var width = expanded && y > padding ? max(measuredWidth, (contentWidth - padding * 2 - gap * 5) / 6) : measuredWidth
                if x > padding && (x + width > contentWidth - padding || columns == 9) {
                    let maxRows = min(5, max(1, Int(((NSScreen.main?.visibleFrame.height ?? 600) - 100) / (height + gap))))
                    if !expanded || Int((y - padding) / (height + gap)) + 1 >= maxRows { break }
                    x = padding; y += height + gap; columns = 0
                    width = max(measuredWidth, (contentWidth - padding * 2 - gap * 5) / 6)
                }
                boxes.append(NSRect(x: x, y: y, width: width, height: height))
                x += width + gap; columns += 1
            }
            size = NSSize(width: maxWidth, height: y + height + padding)
        }
        let visibleStart = first
        if !expanded || style.layout != .horizontal {
            visibleRange = visibleStart..<(visibleStart + boxes.count)
            nextStart = visibleRange.upperBound
        }
        if !visibleRange.contains(highlightedIndex) { highlightedIndex = visibleRange.lowerBound }
        toggleBox = style.layout == .horizontal && !expanded ? NSRect(x: maxWidth - 28, y: padding, width: 26, height: height) : .zero
        // The panel owns its content size. Resizing here would jump to the
        // destination before the window animation starts.
        if !(window is CandidatePanel) { frame.size = size }
        backdrop.frame = bounds
        artwork.frame = bounds
        tint.frame = bounds
        backdrop.alphaValue = tuning.systemMaterial ? 1 : tuning.blur
        backdrop.isHidden = !tuning.systemMaterial && tuning.blur == 0
        tint.isHidden = tuning.systemMaterial
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = tuning.capsule && style.layout == .horizontal ? (expanded ? min(14, height / 2) : size.height / 2) : style.cornerRadius
        layer?.masksToBounds = true
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(snapshot.candidates[visibleRange].map(\.text).joined(separator: "，"))
        artwork.needsDisplay = true
        return size
    }
    private func showScrollIndicator() {
        scrollHideTask?.cancel()
        scrollThumb.layer?.removeAllAnimations()
        scrollThumb.alphaValue = 1
        scrollHideTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
                self.scrollThumb.animator().alphaValue = 0
            } completionHandler: {}
        }
    }
    private func drawCandidates(_ dirtyRect: NSRect) {
        let interval = Performance.input.beginInterval("DrawCandidates")
        defer { Performance.input.endInterval("DrawCandidates", interval) }
        guard let snapshot else { return }
        let tuning = style.tuning
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tint.layer?.backgroundColor = (dark ? tuning.darkBackground : tuning.lightBackground).color.withAlphaComponent(tuning.opacity).cgColor
        layer?.borderColor = tuning.border.color.withAlphaComponent(tuning.borderOpacity).cgColor
        layer?.borderWidth = tuning.borderWidth
        if expanded {
            NSColor.separatorColor.withAlphaComponent(0.18).setStroke()
            for row in Set(boxes.map(\.minY)).sorted().dropFirst() {
                let line = NSBezierPath()
                line.lineWidth = 0.5
                line.move(to: NSPoint(x: 0, y: row - tuning.spacing / 2))
                line.line(to: NSPoint(x: bounds.width, y: row - tuning.spacing / 2))
                line.stroke()
            }
        }
        let wordPadding = max(tuning.wordPadding, style.fontSize * 0.5)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        for (i, box) in boxes.enumerated() {
            let index = visibleRange.lowerBound + i
            let selected = index == highlightedIndex
            if selected { tuning.selection.color.setFill(); NSBezierPath(roundedRect: box, xRadius: min(tuning.selectionRadius, box.height / 2), yRadius: min(tuning.selectionRadius, box.height / 2)).fill() }
            let baseline = box.minY + (box.height - ceil(font.ascender - font.descender)) / 2
            let color = selected ? tuning.selectedText.color : (dark ? tuning.darkText : tuning.lightText).color
            let numberWidth = tuning.showNumbers ? ceil(("1" as NSString).size(withAttributes: [.font: numberFont]).width) + 4 : 0
            if tuning.showNumbers && (!expanded || numberedRange.contains(index)) {
                ("\(expanded ? index - numberedRange.lowerBound + 1 : i + 1)" as NSString).draw(at: NSPoint(x: box.minX + wordPadding, y: box.midY - ("1" as NSString).size(withAttributes: [.font: numberFont]).height / 2), withAttributes: [.font: numberFont, .foregroundColor: color.withAlphaComponent(tuning.numberOpacity)])
            }
            (snapshot.candidates[index].text as NSString).draw(in: NSRect(x: box.minX + wordPadding + numberWidth, y: baseline, width: box.width - wordPadding * 2 - numberWidth, height: box.height), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        }

        if !toggleBox.isEmpty {
            NSColor.separatorColor.setStroke()
            let divider = NSBezierPath(); divider.move(to: NSPoint(x: toggleBox.minX, y: toggleBox.minY + 5)); divider.line(to: NSPoint(x: toggleBox.minX, y: toggleBox.maxY - 5)); divider.stroke()
            let arrow = NSBezierPath(); arrow.lineWidth = 1.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            let mid = toggleBox.midY
            arrow.move(to: NSPoint(x: toggleBox.midX - 4, y: mid + (expanded ? 2 : -2)))
            arrow.line(to: NSPoint(x: toggleBox.midX, y: mid + (expanded ? -2 : 2)))
            arrow.line(to: NSPoint(x: toggleBox.midX + 4, y: mid + (expanded ? 2 : -2)))
            NSColor.secondaryLabelColor.setStroke(); arrow.stroke()
        }
    }
    func moveSelection(_ keyCode: UInt16) -> Bool {
        guard let current = boxes.indices.first(where: { visibleRange.lowerBound + $0 == highlightedIndex }) else { return false }
        let target: Int?
        switch keyCode {
        case 123: target = current > 0 ? current - 1 : nil
        case 124: target = current + 1 < boxes.count ? current + 1 : nil
        case 125, 126:
            let row = boxes[current].minY
            let candidates = boxes.indices.filter { keyCode == 125 ? boxes[$0].minY > row : boxes[$0].minY < row }
            let nextRow = keyCode == 125 ? candidates.map { boxes[$0].minY }.min() : candidates.map { boxes[$0].minY }.max()
            target = candidates.filter { boxes[$0].minY == nextRow }.min { abs(boxes[$0].minX - boxes[current].minX) < abs(boxes[$1].minX - boxes[current].minX) }
        default: return false
        }
        guard let target else { return false }
        highlightedIndex = visibleRange.lowerBound + target
        artwork.needsDisplay = true
        return true
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        togglePressed = toggleBox.contains(point)
        pressed = boxes.firstIndex { $0.contains(point) }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if togglePressed && toggleBox.contains(point) { toggle?() }
        togglePressed = false
        if let pressed, boxes.indices.contains(pressed), boxes[pressed].contains(point) { select?(visibleRange.lowerBound + pressed) }
        pressed = nil
    }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 2, Date().timeIntervalSince(lastScroll) > 0.2 else { return }
        lastScroll = Date(); page?(event.scrollingDeltaY > 0)
    }
}

private final class CandidateArtwork: NSView {
    override var allowsVibrancy: Bool { false }
    var render: ((NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { render?(dirtyRect) }
}
