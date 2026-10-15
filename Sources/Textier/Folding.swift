import AppKit
import TextierCore

/// Lays out JSON text with some of its blocks folded (`foldRegions`): a folded
/// block's text between its brackets isn't drawn, its line breaks don't break
/// lines, and a "⋯" placeholder stands in for it. The text itself is never
/// changed, so editing around a fold, undo, copy and Go to Line see all of it.
/// Folds move with edits around them; an edit that runs into a folded block
/// expands it, and one that unbalances its brackets drops the fold.
final class FoldingLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Posted when blocks fold or expand, for the line numbers.
    static let foldsDidChange = Notification.Name("FoldingLayoutManager.foldsDidChange")
    /// The placeholder's width.
    static let placeholderWidth: CGFloat = 22

    /// Whether the text folds (it's JSON). Off, nothing folds and the gutter has no
    /// chevrons.
    var foldsJSON = false {
        didSet {
            guard foldsJSON != oldValue else { return }
            if foldsJSON { findRegions() } else { regions = []; setFolded([]) }
        }
    }
    /// The text's blocks that fold, by opening bracket; worked out again after each edit.
    private(set) var regions: [FoldRegion] = []
    /// The folded blocks, by opening bracket.
    private(set) var folded: [FoldRegion] = []
    /// The folded blocks not inside another folded one: what's hidden, each with
    /// its placeholder, by opening bracket.
    private var outermost: [FoldRegion] = []

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Folding

    func isFolded(_ region: FoldRegion) -> Bool { folded.contains(region) }

    func fold(_ region: FoldRegion) {
        guard regions.contains(region), !isFolded(region) else { return }
        setFolded(folded + [region])
    }

    func unfold(_ region: FoldRegion) {
        guard isFolded(region) else { return }
        setFolded(folded.filter { $0 != region })
    }

    func toggle(_ region: FoldRegion) {
        isFolded(region) ? unfold(region) : fold(region)
    }

    /// Folds every block but the outermost ones, so the top level shows.
    func foldAll() {
        setFolded(regions.filter { region in regions.contains { $0.open < region.open && region.close < $0.close } })
    }

    func unfoldAll() {
        setFolded([])
    }

    /// Folds `regions` that are still the text's blocks, as after the text was put
    /// back unchanged.
    func refold(_ kept: [FoldRegion]) {
        setFolded(kept.filter(regions.contains))
    }

    /// Expands the folded blocks whose hidden text overlaps `range` (or, for an
    /// empty range, holds its location inside).
    func unfold(revealing range: NSRange) {
        let hiding = folded.filter { region in
            let hidden = region.hidden
            return range.length == 0
                ? range.location > hidden.location && range.location < NSMaxRange(hidden)
                : NSIntersectionRange(range, hidden).length > 0
        }
        guard !hiding.isEmpty else { return }
        setFolded(folded.filter { !hiding.contains($0) })
    }

    /// The folded block whose hidden text holds `location` inside it (not at its
    /// ends, which show), outermost first.
    func foldHiding(_ location: Int) -> FoldRegion? {
        outermost.first { location > $0.hidden.location && location < NSMaxRange($0.hidden) }
    }

    /// The first block that opens in `characters` (the outermost of a line's).
    func region(openingIn characters: NSRange) -> FoldRegion? {
        regions.first { NSLocationInRange($0.open, characters) }
    }

    /// The placeholder at `point` (in text container coordinates), as its block.
    func placeholder(at point: NSPoint) -> FoldRegion? {
        guard let container = textContainers.first else { return nil }
        return outermost.first { placeholderRect(of: $0, in: container)?.contains(point) == true }
    }

    /// Where `region`'s placeholder is drawn, in text container coordinates.
    func placeholderRect(of region: FoldRegion, in container: NSTextContainer) -> NSRect? {
        guard outermost.contains(region), region.hidden.length > 0 else { return nil }
        let glyph = glyphIndexForCharacter(at: region.hidden.location)
        return boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
    }

    private func setFolded(_ next: [FoldRegion]) {
        let next = Array(Set(next)).sorted { $0.open < $1.open }
        guard next != folded else { return }
        let changed = Set(folded).symmetricDifference(next)
        folded = next
        outermost = Self.outermost(of: next)
        guard let length = textStorage?.length, length > 0, let first = changed.map(\.open).min(),
              let last = changed.map(\.close).max() else { return notify() }
        let range = NSIntersectionRange(NSRange(location: first, length: last - first + 1), NSRange(location: 0, length: length))
        invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        notify()
    }

    private func notify() {
        // Folding happens on the main thread only: from clicks, keys and edits.
        let textViews = textContainers.compactMap(\.textView)
        MainActor.assumeIsolated {
            for textView in textViews {
                textView.needsDisplay = true
                textView.window?.invalidateCursorRects(for: textView)
            }
        }
        NotificationCenter.default.post(name: Self.foldsDidChange, object: self)
    }

    private static func outermost(of folded: [FoldRegion]) -> [FoldRegion] {
        var outermost: [FoldRegion] = []
        for region in folded where outermost.last.map({ region.open > $0.close }) ?? true {
            outermost.append(region)
        }
        return outermost
    }

    private func findRegions() {
        regions = foldsJSON ? foldRegions(in: (textStorage?.string ?? "") as NSString) : []
    }

    // MARK: Following edits

    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
        changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange
    ) {
        guard foldsJSON, editMask.contains(.editedCharacters) else {
            return super.processEditing(
                for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
                invalidatedRange: invalidatedCharRange
            )
        }
        // Each fold, moved past the edit: kept when the edit is wholly before or
        // after it, and still one of the text's blocks.
        let start = newCharRange.location
        let oldEnd = NSMaxRange(newCharRange) - delta
        let moved = folded.compactMap { region -> FoldRegion? in
            if oldEnd <= region.open { return FoldRegion(open: region.open + delta, close: region.close + delta) }
            if start > region.close { return region }
            return nil
        }
        findRegions()
        let kept = moved.filter(regions.contains)
        let dropped = kept.count < folded.count
        folded = kept
        outermost = Self.outermost(of: kept)
        super.processEditing(
            for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
            invalidatedRange: invalidatedCharRange
        )
        guard dropped else { return }
        // A dropped fold's text shows again.
        let whole = NSRange(location: 0, length: textStorage.length)
        invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
        notify()
    }

    // MARK: Hiding and the placeholder

    /// Whether `index` is hidden: nil when it shows, true for a hidden range's first
    /// character, where the placeholder goes, false for the rest.
    private func hiding(_ index: Int) -> Bool? {
        var low = 0, high = outermost.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(outermost[middle].hidden) <= index { low = middle + 1 } else { high = middle }
        }
        guard low < outermost.count, NSLocationInRange(index, outermost[low].hidden) else { return nil }
        return index == outermost[low].hidden.location
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont, forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !outermost.isEmpty, glyphRange.length > 0 else { return 0 }
        var properties: [NSLayoutManager.GlyphProperty]?
        for index in 0..<glyphRange.length {
            guard let hidden = hiding(charIndexes[index]) else { continue }
            if properties == nil { properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            properties?[index] = hidden ? .controlCharacter : .null
        }
        guard let properties else { return 0 }
        setGlyphs(glyphs, properties: properties, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let isPlaceholder = hiding(charIndex) else { return action }
        // The placeholder takes room; a hidden line break doesn't break the line.
        return isPlaceholder ? .whitespace : .zeroAdvancement
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int
    ) -> NSRect {
        let width = hiding(charIndex) == true ? Self.placeholderWidth : 0
        return NSRect(x: glyphPosition.x, y: 0, width: width, height: proposedRect.height)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first, let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for region in outermost where NSLocationInRange(region.hidden.location, characters) {
            guard let rect = placeholderRect(of: region, in: container) else { continue }
            let font = storage.attribute(.font, at: region.hidden.location, effectiveRange: nil) as? NSFont
                ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
            let lineHeight = defaultLineHeight(for: font)
            let pill = NSRect(x: rect.minX + 2, y: rect.minY + (rect.height - lineHeight) / 2 + 2,
                              width: rect.width - 4, height: lineHeight - 4).offsetBy(dx: origin.x, dy: origin.y)
            NSColor.labelColor.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
            let dots = "⋯" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: font.pointSize, weight: .bold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7),
            ]
            let size = dots.size(withAttributes: attributes)
            dots.draw(at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

/// A text view whose JSON folds (`FoldingLayoutManager`). A click on a "⋯"
/// expands it, and so does the cursor or a selection's end moving into a folded
/// block (an arrow moving onto one steps over it instead). Fold and Unfold's
/// shortcuts (⌥⌘[ and ⌥⌘], the Config's `shortcuts`) work on the block at the
/// cursor.
final class FoldingTextView: OwnCopyTextView {
    var folding: FoldingLayoutManager? { layoutManager as? FoldingLayoutManager }

    /// A TextKit 1 text view with a folding layout manager; `foldsJSON` turns folding on.
    static func make(foldsJSON: Bool) -> FoldingTextView {
        let textView = FoldingTextView(usingTextLayoutManager: false)
        let folding = FoldingLayoutManager()
        textView.textContainer?.replaceLayoutManager(folding)
        folding.foldsJSON = foldsJSON
        return textView
    }

    private var isRevealing = false

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        let previous = selectedRange()
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        guard !stillSelectingFlag, !isRevealing, let folding, !folding.folded.isEmpty else { return }
        isRevealing = true
        defer { isRevealing = false }
        let selection = selectedRange()
        // An arrow moving onto a fold, from either side, steps over it.
        if previous.length == 0, selection.length == 0, let region = folding.foldHiding(selection.location) {
            if previous.location == region.hidden.location, selection.location == region.hidden.location + 1 {
                return setSelectedRange(NSRange(location: NSMaxRange(region.hidden), length: 0))
            }
            if previous.location == NSMaxRange(region.hidden), selection.location == NSMaxRange(region.hidden) - 1 {
                return setSelectedRange(NSRange(location: region.hidden.location, length: 0))
            }
        }
        for end in Set([selection.location, NSMaxRange(selection)]) {
            folding.unfold(revealing: NSRange(location: end, length: 0))
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let folding, let region = folding.placeholder(at: containerPoint(of: event)) {
            folding.unfold(region)
            return
        }
        super.mouseDown(with: event)
    }

    private func containerPoint(of event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        return NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let folding, let container = textContainer else { return }
        for region in folding.folded {
            guard let rect = folding.placeholderRect(of: region, in: container) else { continue }
            addCursorRect(rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y), cursor: .pointingHand)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, folding?.foldsJSON == true, let shortcut = Shortcut(event: event),
              let command = AppConfig.current.shortcuts.command(for: shortcut)
        else { return super.performKeyEquivalent(with: event) }
        switch command {
        case .fold: foldAtCursor()
        case .unfold: unfoldAtCursor()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: At the cursor

    /// The lines `location` and each block's brackets are on, by line start.
    private func line(of location: Int, in starts: [Int]) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= location { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Folds the innermost expanded block the cursor's line is in (its opening
    /// line up to the line before its closing bracket's), the cursor moving to
    /// just after its opening bracket.
    func foldAtCursor() {
        guard let folding else { return }
        let starts = LineNumberRuler.lineStarts(in: string as NSString)
        let cursor = line(of: selectedRange().location, in: starts)
        let candidates = folding.regions.filter { region in
            !folding.isFolded(region) && line(of: region.open, in: starts) <= cursor && cursor < line(of: region.close, in: starts)
        }
        guard let region = candidates.last else { return NSSound.beep() }
        let selection = selectedRange()
        folding.fold(region)
        // A cursor or selection end the fold hid moves out before it.
        let hidden = region.hidden
        if [selection.location, NSMaxRange(selection)].contains(where: { $0 > hidden.location && $0 < NSMaxRange(hidden) }) {
            setSelectedRange(NSRange(location: hidden.location, length: 0))
        }
    }

    /// Expands the folded blocks that open on the cursor's line, or else the
    /// innermost one the cursor's line is in.
    func unfoldAtCursor() {
        guard let folding else { return }
        let starts = LineNumberRuler.lineStarts(in: string as NSString)
        let cursor = line(of: selectedRange().location, in: starts)
        let onLine = folding.folded.filter { line(of: $0.open, in: starts) == cursor }
        if !onLine.isEmpty { return onLine.forEach(folding.unfold) }
        let around = folding.folded.filter { line(of: $0.open, in: starts) <= cursor && cursor <= line(of: $0.close, in: starts) }
        guard let region = around.last else { return NSSound.beep() }
        folding.unfold(region)
    }
}
