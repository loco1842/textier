import AppKit
import TextierCore

/// The Input's line numbers, in a gutter on its left. A line that wraps is
/// numbered on its first row only. The cursor's line stands out (brighter and
/// semibold on a soft highlight, as in a code editor); the rest stay quiet. In the
/// Input it draws no background or edge, so the Panel's frosted background shows
/// through; a Raw view's gutter (`showsGutter`) is a faint band with an edge, and
/// its numbers are brighter, so they stand out on the card in either appearance.
///
/// When the text folds (Raw JSON, `FoldingLayoutManager`), a chevron follows the
/// number of each line a block opens on: while the pointer is over the gutter, and
/// always on a folded one. A click on it folds or expands the block.
@MainActor
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    /// Where each line starts, as UTF-16 offsets; rebuilt when the text changes.
    private(set) var lineStarts: [Int] = [0]

    /// AppKit lays the ruler over the clip view, not beside it, so text scrolled
    /// sideways would run under the numbers. The clip view is masked out under the
    /// gutter, and while scrolled sideways the text fades in just past it.
    private let gutterMask = CAGradientLayer()
    /// How far past the gutter the text fades in, while scrolled sideways.
    static let gutterFade: CGFloat = 12

    /// A Raw view's gutter: a faint band with an edge, and brighter numbers.
    var showsGutter = false {
        didSet { needsDisplay = true }
    }

    /// The chevrons' column, after the numbers, when the text folds.
    static let chevronWidth: CGFloat = 12
    /// The pointer is over the gutter: every foldable line shows its chevron.
    private(set) var isHovering = false {
        didSet { if isHovering != oldValue { needsDisplay = true } }
    }

    /// The text's folding, when it folds.
    var folding: FoldingLayoutManager? {
        (textView?.layoutManager as? FoldingLayoutManager).flatMap { $0.foldsJSON ? $0 : nil }
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private static let currentFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

    /// The 1-based line the cursor (or the selection's start) is on.
    var currentLine: Int {
        lineNumber(at: textView?.selectedRange().location ?? 0)
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // Views don't clip by default (macOS 14), and a number half past the edge
        // would draw over what's below.
        clipsToBounds = true
        // No markers or accessory: the numbers are all it holds.
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange), name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionDidChange), name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(foldsDidChange), name: FoldingLayoutManager.foldsDidChange,
            object: textView.layoutManager
        )
        if let clipView = scrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidChange), name: name, object: clipView)
            }
        }
        countLines()
    }

    @objc private func clipViewDidChange() {
        maskClipView()
    }

    /// Masks the clip view under the gutter (see `gutterMask`).
    func maskClipView() {
        guard let scrollView, let clipView = scrollView.contentView as NSClipView? else { return }
        clipView.wantsLayer = true
        guard let layer = clipView.layer, clipView.frame.width > 0 else { return }
        // The gutter's edge in the clip view, which may start under it.
        let edge = max(0, frame.maxX - clipView.frame.minX)
        let fade = clipView.bounds.minX > 0.5 ? Self.gutterFade : 0
        let width = clipView.frame.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gutterMask.startPoint = CGPoint(x: 0, y: 0.5)
        gutterMask.endPoint = CGPoint(x: 1, y: 0.5)
        gutterMask.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        gutterMask.locations = [0, NSNumber(value: min(1, edge / width)), NSNumber(value: min(1, (edge + fade) / width)), 1]
        gutterMask.frame = layer.bounds
        layer.mask = edge > 0 ? gutterMask : nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        maskClipView()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func textDidChange() {
        countLines()
    }

    @objc private func selectionDidChange() {
        needsDisplay = true
    }

    @objc private func foldsDidChange() {
        needsDisplay = true
    }

    /// Tells the ruler when the pointer is over it, for `isHovering`.
    private lazy var hoverArea = NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
    )

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(hoverArea) { addTrackingArea(hoverArea) }
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// A click on a line blocks open on folds or expands them
    /// (`FoldingLayoutManager.toggle(line:)`).
    override func mouseDown(with event: NSEvent) {
        let blocks = regions(at: convert(event.locationInWindow, from: nil))
        guard let folding, !blocks.isEmpty else { return super.mouseDown(with: event) }
        folding.toggle(line: blocks)
    }

    /// The blocks that open in view on the line at `point`, in the ruler's
    /// coordinates, outermost first.
    func regions(at point: NSPoint) -> [FoldRegion] {
        guard let textView, let folding, let container = textView.textContainer, folding.numberOfGlyphs > 0 else { return [] }
        let inText = textView.convert(point, from: self)
        let origin = textView.textContainerOrigin
        let glyph = folding.glyphIndex(for: NSPoint(x: 0, y: inText.y - origin.y), in: container)
        let fragment = folding.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard inText.y - origin.y >= fragment.minY, inText.y - origin.y < fragment.maxY else { return [] }
        return regions(onLineOf: folding.characterIndexForGlyph(at: glyph))
    }

    /// The blocks that open in view on the line `index` is on.
    private func regions(onLineOf index: Int) -> [FoldRegion] {
        let line = lineNumber(at: index)
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] : (textView?.string as NSString?)?.length ?? start
        return folding?.regions(openingIn: NSRange(location: start, length: end - start)) ?? []
    }

    private func countLines() {
        lineStarts = Self.lineStarts(in: (textView?.string ?? "") as NSString)
        // Room for the widest number, at least two digits.
        let digits = max(2, String(lineStarts.count).count)
        // 8 pt before the number, 6 after, so the text follows close behind.
        let width = ceil(("8" as NSString).size(withAttributes: [.font: Self.font]).width) * CGFloat(digits) + 14
            + (folding == nil ? 0 : Self.chevronWidth)
        if ruleThickness != width {
            ruleThickness = width
            maskClipView()
        }
        needsDisplay = true
    }

    /// The offset each line of `text` starts at: 0, then after every line break.
    static func lineStarts(in text: NSString) -> [Int] {
        var starts = [0]
        for index in 0..<text.length where text.isLineBreak(at: index) {
            starts.append(index + 1)
        }
        return starts
    }

    /// The 1-based line `index` is on.
    func lineNumber(at index: Int) -> Int {
        Self.line(of: index, in: lineStarts) + 1
    }

    /// The 0-based line `index` is on, in a text whose lines start at `starts`.
    static func line(of index: Int, in starts: [Int]) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= index { low = middle } else { high = middle - 1 }
        }
        return low
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsGutter {
            NSColor.labelColor.withAlphaComponent(0.05).setFill()
            bounds.fill()
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSRect(x: bounds.maxX - 0.5, y: bounds.minY, width: 0.5, height: bounds.height).fill()
        }
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return
        }
        let quiet: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: showsGutter ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
        ]
        let current: [NSAttributedString.Key: Any] = [
            .font: Self.currentFont, .foregroundColor: showsGutter ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let currentLine = self.currentLine
        let origin = textView.textContainerOrigin
        let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? Self.font)
        let labelHeight = Self.font.ascender - Self.font.descender
        let folding = self.folding
        let chevrons = folding == nil ? 0 : Self.chevronWidth
        func label(_ number: Int, atLineTop top: CGFloat, start: Int) {
            let y = convert(NSPoint(x: 0, y: top + origin.y), from: textView).y + (lineHeight - labelHeight) / 2
            if let folding, case let blocks = regions(onLineOf: start), !blocks.isEmpty {
                // Folded when one of the line's blocks is, as a click then opens it.
                let isFolded = blocks.contains(where: folding.isFolded)
                if isFolded || isHovering { drawChevron(folded: isFolded, centerY: y + labelHeight / 2) }
            }
            let isCurrent = number == currentLine
            let attributes = isCurrent ? current : quiet
            let text = String(number) as NSString
            let width = text.size(withAttributes: attributes).width
            let x = ruleThickness - width - 6 - chevrons
            if isCurrent {
                // A soft pill behind the cursor's line number.
                let pill = NSRect(x: x - 4, y: y - 1.5, width: width + 8, height: labelHeight + 3)
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            }
            text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }

        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let string = textView.string as NSString
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, fragmentGlyphs, _ in
            let start = layoutManager.characterIndexForGlyph(at: fragmentGlyphs.location)
            // Only a line's first row: the text's start, or right after a line break.
            guard start == 0 || string.isLineBreak(at: start - 1) else { return }
            label(self.lineNumber(at: start), atLineTop: fragment.minY, start: start)
        }
        // The empty line after a final line break has its own fragment.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty, extra.intersects(visible.offsetBy(dx: -origin.x, dy: -origin.y)) {
            label(lineStarts.count, atLineTop: extra.minY, start: lineStarts[lineStarts.count - 1])
        }
    }

    /// A chevron in its column, pointing right on a folded line, down on one to fold.
    private func drawChevron(folded: Bool, centerY: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(.init(paletteColors: [folded ? NSColor.labelColor : NSColor.secondaryLabelColor]))
        guard let image = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let rect = NSRect(
            x: ruleThickness - Self.chevronWidth - 3 + (Self.chevronWidth - size.width) / 2, y: centerY - size.height / 2,
            width: size.width, height: size.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

extension NSString {
    /// Whether a line ends at `index`, as the text system breaks lines: a line feed,
    /// a carriage return not followed by one (so a CRLF counts once, at its LF), a
    /// next line (NEL), or a Unicode line or paragraph separator.
    fileprivate func isLineBreak(at index: Int) -> Bool {
        switch character(at: index) {
        case 10, 0x85, 0x2028, 0x2029: true
        case 13: index + 1 >= length || character(at: index + 1) != 10
        default: false
        }
    }
}
