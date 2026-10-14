import AppKit
import TextierCore

/// The Panel's editable Input, with its top-level Matches drawn as rounded pills in
/// their Pattern's tint, their text in its text color, while Highlighting is on. A
/// Match that wraps gets a pill piece on each line. The pill under the pointer and
/// the entry selected in the Inspector (`inspected`, a nested Match too) take the
/// strong tint; the selected one also gets a ring in the solid color.
///
/// A click is a text view's click everywhere, Matches included: it places the
/// cursor, a drag selects, a double-click selects a word. With Highlighting on and
/// the Match click's modifiers held (⌘ by default, the Config's
/// `shortcuts.matchClick`), the pointer over a Match is the pointing hand, its pill
/// deepens, and a click opens it in the Inspector.
@MainActor
final class InputTextView: OwnCopyTextView {
    var matches: [Match] = [] {
        didSet {
            // An inspection describes the text as it is: the Panel and the Selection Popover
            // drop one that started before an edit. So the range check is enough.
            let length = (string as NSString).length
            live = matches.filter { NSMaxRange($0.range) <= length }
                .sorted { $0.range.location < $1.range.location }
            if let hovered, match(containing: hovered.location)?.range != hovered { self.hovered = nil }
            highlight()
            fadeInNewPills()
            updatePointingHandRects()
        }
    }

    var highlighting = true {
        didSet {
            guard highlighting != oldValue else { return }
            if !highlighting {
                isActingOnMatches = false
                hover(nil)
            }
            highlight()
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Whether long lines wrap at the Input's width, or run on and scroll sideways.
    var wrapsLines = true {
        didSet { applyWrapping() }
    }

    /// The entry selected in the Inspector: its range and its Pattern's color.
    var inspected: (range: NSRange, color: PatternColor)? {
        get { selection }
        set {
            let old = selection
            selection = newValue
            reselect(from: old?.range)
        }
    }

    /// `inspected`, which edits move along without highlighting everything again.
    private var selection: (range: NSRange, color: PatternColor)?

    /// Set around a re-inspection while editing, so the pills it brings fade in;
    /// a capture's pills show at once.
    var fadesNewPills = false
    /// The Matches whose pills showed last time, to tell new pills from ones that
    /// only moved.
    private var shownPills: [Match] = []
    private var fade: Timer?

    /// The top-level Match under the pointer.
    private var hovered: NSRange?

    /// The Matches that still describe the text, by position: `matches` checked
    /// against the text when they're set, then moved along by each edit, less those
    /// an edit touched, until the debounced re-inspection sets them afresh. Only their
    /// own ranges move, not their children's.
    private var live: [Match] = []
    /// The text the edits since the last redraw touched: the Matches they took the
    /// pills of, and what they put in. `didChangeText` recolors it.
    private var editedText: NSRange?

    /// The pills drawn behind the text, in drawing order; empty with Highlighting off.
    var pills: [Pill] { pillLayoutManager?.pills ?? [] }

    private var pillLayoutManager: PillLayoutManager? { layoutManager as? PillLayoutManager }

    /// Each range whose text is colored again; the app tests watch it.
    var onRecolor: (NSRange) -> Void = { _ in }
    /// A click on a Match with the Match click's modifiers held.
    var onClick: (Match) -> Void = { _ in }
    /// Esc, when something outside the text view handles it (the Selection
    /// Popover closing); nil leaves it to NSTextView.
    var onCancel: (() -> Void)?
    /// NSTextView's own mouse tracking (a click places the cursor, a drag selects,
    /// a double-click selects a word). Its tracking loop reads the real pointer, so
    /// the app tests stand in for it; nil runs NSTextView's.
    var trackMouse: ((NSEvent) -> Void)?

    /// Reports pointer moves, so the cursor can follow Matches.
    private var pointerTracking: NSTrackingArea?

    /// A plain-text view for the Input. It uses TextKit 1, because hit-testing and
    /// temporary attributes need an `NSLayoutManager`.
    static func make() -> InputTextView {
        let storage = NSTextStorage()
        let layoutManager = PillLayoutManager()
        layoutManager.delegate = layoutManager
        // Only the text in view (and what leads to it) is laid out, so a large Input
        // scrolls anywhere at once.
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = InputTextView(frame: .zero, textContainer: container)
        layoutManager.onEdit = { [weak textView] in textView?.follow($0) }
        textView.isRichText = false
        textView.allowsUndo = true
        // The Panel's frosted background shows through.
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        // The first line's spacing goes above it, so lines sit centered in their 1.75 height.
        textView.textContainerInset = NSSize(width: 6, height: 14 + PillLayoutManager.lineSpacing / 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }

    override func mouseDown(with event: NSEvent) {
        updateModifiers(event.modifierFlags)
        guard isActingOnMatches, event.clickCount == 1,
              let match = match(at: convert(event.locationInWindow, from: nil))
        else {
            // NSTextView tracks the mouse until it goes up: a click places the cursor, a drag selects.
            track(event)
            return
        }
        onClick(match)
    }

    /// The Match click's modifiers are held (and Highlighting is on): the pointer
    /// over a Match shows it can be clicked.
    private var isActingOnMatches = false

    /// The modifiers held changed: the pointing hand and the hovered pill follow.
    func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        let acting = highlighting && Shortcut.areHeld(AppConfig.current.shortcuts.matchClick, in: flags)
        guard acting != isActingOnMatches else { return }
        isActingOnMatches = acting
        window?.invalidateCursorRects(for: self)
        guard let pointer = pointerLocation() else { return }
        if acting {
            let index = characterIndex(at: pointer)
            hover(index.flatMap(match(containing:))?.range)
        } else {
            hover(nil)
        }
        showCursor(at: pointer)
    }

    /// Where the pointer is, in this view's coordinates; the app tests set it, as
    /// the real pointer is wherever the person at the Mac left it.
    lazy var pointerLocation: () -> NSPoint? = { [weak self] in
        guard let self, let window = self.window else { return nil }
        return self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    /// The hand over a Match while the Match click's modifiers are held, else the
    /// I-beam; only with the pointer over the text. Set outright, since cursor rects
    /// change it only as the pointer enters one, and the text view puts its I-beam
    /// back as the pointer moves.
    private func showCursor(at point: NSPoint) {
        guard visibleRect.contains(point) else { return }
        (isActingOnMatches && match(at: point) != nil ? NSCursor.pointingHand : NSCursor.iBeam).set()
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateModifiers(event.modifierFlags)
    }

    private func track(_ event: NSEvent) {
        if let trackMouse { trackMouse(event) } else { super.mouseDown(with: event) }
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard pointerTracking == nil else { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    /// Deepens the pill under the pointer, and shows the hand over it while the
    /// Match click's modifiers are held.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateModifiers(event.modifierFlags)
        let point = convert(event.locationInWindow, from: nil)
        showCursor(at: point)
        let index = isActingOnMatches ? characterIndex(at: point) : nil
        // Still over the same pill: nothing to look up.
        if let index, let hovered, NSLocationInRange(index, hovered) { return }
        hover(index.flatMap(match(containing:))?.range)
    }

    /// Deepens the pill at `range` instead of the one hovered before, redrawing just
    /// those two.
    private func hover(_ range: NSRange?) {
        guard range != hovered else { return }
        if let hovered { pillLayoutManager?.setStrong(false, forPillAt: hovered) }
        hovered = range
        if let range { pillLayoutManager?.setStrong(true, forPillAt: range) }
    }

    /// The I-beam everywhere, as for any text view, and the pointing hand over the
    /// visible pills, as NSTextView does for links: the window picks between them
    /// as the pointer moves.
    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in pointingHandRects { addCursorRect(rect, cursor: .pointingHand) }
    }

    /// The visible pills' pieces, in this view's coordinates, while the Match
    /// click's modifiers are held; none otherwise, or with Highlighting off.
    var pointingHandRects: [NSRect] {
        guard isActingOnMatches, let pillLayoutManager, let textContainer else { return [] }
        let visible = visibleRect
        let origin = textContainerOrigin
        let shown = pillLayoutManager.glyphRange(
            forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer
        )
        let characters = pillLayoutManager.characterRange(forGlyphRange: shown, actualGlyphRange: nil)
        var rects: [NSRect] = []
        // Only the Matches in view, and only their lines in view.
        var index = live.firstIndex(endingAfter: characters.location, range: \.range)
        while index < live.endIndex, live[index].range.location < NSMaxRange(characters) {
            rects += pillLayoutManager.pieces(of: NSIntersectionRange(live[index].range, characters)).map {
                $0.offsetBy(dx: origin.x, dy: origin.y).intersection(visible)
            }
            index += 1
        }
        return rects.filter { !$0.isEmpty }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover(nil)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isOverMatch(event) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    private func isOverMatch(_ event: NSEvent) -> Bool {
        isActingOnMatches && match(at: convert(event.locationInWindow, from: nil)) != nil
    }

    /// Lays out the pills and colors the Matches' text, or clears both with
    /// Highlighting off.
    private func highlight() {
        guard let pillLayoutManager else { return }
        editedText = nil
        pillLayoutManager.pills = makePills()
        let whole = NSRange(location: 0, length: textStorage?.length ?? 0)
        pillLayoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        colored = IndexSet()
        colorVisibleText()
        needsDisplay = true
    }

    /// The text whose pills' colors are applied since the last `highlight()`, by
    /// UTF-16 offset: a large Input's pills are colored as their text is about to
    /// be drawn (`viewWillDraw`), not all at once.
    private var colored = IndexSet()
    /// How far past the visible text pills are colored ahead, either way.
    private static let colorMargin = 20_000

    /// Colors the pills over the visible text and a margin around it, where they
    /// aren't yet.
    private func colorVisibleText() {
        guard let layoutManager, let textContainer, let length = textStorage?.length, length > 0 else { return }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let start = max(0, visible.location - Self.colorMargin)
        let end = min(length, NSMaxRange(visible) + Self.colorMargin)
        guard start < end else { return }
        var missing = IndexSet(integersIn: start..<end)
        missing.subtract(colored)
        for range in missing.rangeView {
            recolor(NSRange(location: range.lowerBound, length: range.count))
        }
    }

    override func viewWillDraw() {
        colorVisibleText()
        super.viewWillDraw()
    }

    /// Scrolling colors what comes into view, before it's drawn.
    private var scrolling: NotificationObservation?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clipView = enclosingScrollView?.contentView else {
            scrolling = nil
            return
        }
        clipView.postsBoundsChangedNotifications = true
        scrolling = NotificationObservation(NSView.boundsDidChangeNotification, object: clipView) { [weak self] in
            self?.colorVisibleText()
        }
    }

    /// Moves the ring from the Match at `old` to the selected one: the pills are
    /// laid out again, but only the two Matches' text is colored again, so a
    /// selection on a large Input doesn't recolor all of it.
    private func reselect(from old: NSRange?) {
        guard let pillLayoutManager else { return }
        pillLayoutManager.pills = makePills()
        let length = textStorage?.length ?? 0
        for range in [old, selection?.range].compactMap(\.self) where NSMaxRange(range) <= length {
            recolor(range)
        }
        needsDisplay = true
    }

    /// The pills, in drawing order: the Matches' by position, then the selected
    /// Match's own, with its ring, over its parent's. None with Highlighting off.
    private func makePills() -> [Pill] {
        guard highlighting else { return [] }
        var pills: [Pill] = []
        pills.reserveCapacity(live.count + 1)
        for match in live where match.range != selection?.range {
            pills.append(Pill(
                range: match.range, color: match.color ?? Palette.fallback, isStrong: match.range == hovered,
                hasRing: false
            ))
        }
        if let selection, NSMaxRange(selection.range) <= textStorage?.length ?? 0 {
            pills.append(Pill(range: selection.range, color: selection.color, isStrong: true, hasRing: true))
        }
        return pills
    }

    /// Colors the text of the pills over `range` in their Patterns' text colors, and
    /// the rest of it plainly.
    private func recolor(_ range: NSRange) {
        guard let pillLayoutManager else { return }
        onRecolor(range)
        if range.length > 0 { colored.insert(integersIn: range.location..<NSMaxRange(range)) }
        pillLayoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for pill in pillLayoutManager.pills(overlapping: range) {
            pillLayoutManager.addTemporaryAttribute(
                .foregroundColor, value: NSColor.pattern(pill.color, \.text),
                forCharacterRange: NSIntersectionRange(pill.range, range)
            )
        }
    }

    /// Moves the Matches, the selected entry and the hovered pill along with an edit
    /// as soon as the text storage takes it in, so no pill sits over the wrong text.
    /// Those the edit touched lose their pills until the re-inspection; their text
    /// loses its color in `didChangeText`, once the edit is done.
    private func follow(_ edit: TextEdit) {
        var touched = edit.range
        let first = live.firstIndex(endingAfter: edit.range.location, range: \.range)
        var end = first
        while end < live.endIndex, edit.moved(live[end].range) == nil {
            touched = NSUnionRange(touched, edit.extent(of: live[end].range))
            end += 1
        }
        live.removeSubrange(first..<end)
        for index in first..<live.endIndex { live[index].range.location += edit.delta }
        if let old = selection {
            selection = edit.moved(old.range).map { ($0, old.color) }
            if selection == nil { touched = NSUnionRange(touched, edit.extent(of: old.range)) }
        }
        hovered = hovered.flatMap(edit.moved)
        editedText = editedText.map { NSUnionRange(edit.extent(of: $0), touched) } ?? touched
        // What's colored moves with the text after the edit.
        colored.shift(startingAt: NSMaxRange(edit.range) - edit.delta, by: edit.delta)
        guard let pillLayoutManager else { return }
        pillLayoutManager.fadingRanges = Set(pillLayoutManager.fadingRanges.compactMap(edit.moved))
        // Only data here: the layout manager is still taking the edit in.
        pillLayoutManager.pills = makePills()
    }

    /// The pills moved or changed: the pointing hand's rects follow.
    private func updatePointingHandRects() {
        window?.invalidateCursorRects(for: self)
    }

    /// Fades in the pills new Matches brought: those whose text and Pattern weren't
    /// showing before (more of them than before, for repeats). Matches that only
    /// moved, as typing before them moves them, don't fade.
    private func fadeInNewPills() {
        guard let pillLayoutManager else { return }
        let shown = highlighting ? live : []
        let previous = shownPills
        shownPills = shown
        guard fadesNewPills, !Motion.isReduced else { return }
        // Counted only for a fade: a capture's hundreds of thousands of pills
        // show at once.
        func key(_ match: Match) -> Int {
            var hasher = Hasher()
            hasher.combine(match.patternIndex)
            hasher.combine(match.text)
            return hasher.finalize()
        }
        var before = previous.reduce(into: [Int: Int]()) { $0[key($1), default: 0] += 1 }
        var fresh: Set<NSRange> = []
        for match in shown {
            if let count = before[key(match)], count > 0 {
                before[key(match)] = count - 1
            } else {
                fresh.insert(match.range)
            }
        }
        guard !fresh.isEmpty else { return }
        pillLayoutManager.fadingRanges = fresh
        pillLayoutManager.fadeProgress = 0
        let start = Date()
        fade?.invalidate()
        // A run loop timer, so the fade also runs while the app tests hold the main queue.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let manager = self.pillLayoutManager else { return }
                let progress = min(1, Date().timeIntervalSince(start) / 0.2)
                // Ease out: quick at first, settling at the end.
                manager.fadeProgress = 1 - pow(1 - progress, 3)
                if progress >= 1 {
                    self.fade?.invalidate()
                    let ranges = manager.fadingRanges
                    manager.fadingRanges = []
                    self.redraw(ranges)
                } else {
                    self.redraw(manager.fadingRanges)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fade = timer
    }

    private func redraw(_ ranges: Set<NSRange>) {
        for range in ranges { layoutManager?.invalidateDisplay(forCharacterRange: range) }
    }

    // MARK: Wrapping

    private func applyWrapping() {
        guard let textContainer else { return }
        let scrollView = enclosingScrollView
        isHorizontallyResizable = !wrapsLines
        textContainer.widthTracksTextView = wrapsLines
        scrollView?.hasHorizontalScroller = !wrapsLines
        if wrapsLines {
            let width = scrollView?.contentSize.width ?? frame.width
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            setFrameSize(NSSize(width: width, height: frame.height))
        } else {
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        sizeToFit()
        needsDisplay = true
        scrollView?.verticalRulerView?.needsDisplay = true
        updatePointingHandRects()
    }

    // MARK: Placeholder

    static let placeholder = "Paste or type text — ⌘V"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        (Self.placeholder as NSString).draw(at: origin, withAttributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    override func didChangeText() {
        // The pills moved with their text; the text of those the edit took away, and
        // what it put in, loses its color.
        if let edited = editedText {
            editedText = nil
            let touched = NSIntersectionRange(edited, NSRange(location: 0, length: textStorage?.length ?? 0))
            recolor(touched)
            layoutManager?.invalidateDisplay(forCharacterRange: touched)
        }
        super.didChangeText()
        updatePointingHandRects()
        // The placeholder comes and goes with the text.
        if string.isEmpty || (string as NSString).length == 1 { needsDisplay = true }
    }

    private func match(at point: NSPoint) -> Match? {
        characterIndex(at: point).flatMap(match(containing:))
    }

    /// The character under `point`, if it's over one.
    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer
        )
        // glyphIndex(for:) snaps to the nearest glyph, so reject clicks beyond the line's end.
        guard glyphRect.contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    /// The top-level Match `index` is in.
    private func match(containing index: Int) -> Match? {
        let found = live.firstIndex(endingAfter: index, range: \.range)
        guard found < live.endIndex, live[found].range.location <= index else { return nil }
        return live[found]
    }
}

/// An edit to the text, as the text storage reports it: the new text is `range`,
/// which replaced `range.length - delta` characters at the same place.
struct TextEdit: Sendable {
    var range: NSRange
    var delta: Int

    /// Where a range of the text before the edit is after it: where it was, or moved
    /// by `delta` when it came after the edit; nil when the edit touched it (typed
    /// inside it, or replaced or deleted any of it). Typing at its start or end
    /// doesn't touch it.
    func moved(_ old: NSRange) -> NSRange? {
        if NSMaxRange(old) <= range.location { return old }
        if old.location >= NSMaxRange(range) - delta { return NSRange(location: old.location + delta, length: old.length) }
        return nil
    }

    /// The text after the edit that a range of the text before it spans: where it
    /// moved, or, when the edit touched it, what's left of it and what the edit put in.
    func extent(of old: NSRange) -> NSRange {
        if let moved = moved(old) { return moved }
        let start = min(old.location, range.location)
        return NSRange(location: start, length: max(NSMaxRange(old) + delta, NSMaxRange(range)) - start)
    }
}

extension RandomAccessCollection where Index == Int {
    /// For elements in text order whose ranges don't overlap: the index of the first
    /// whose range ends after `location`, by binary search.
    fileprivate func firstIndex(endingAfter location: Int, range: (Element) -> NSRange) -> Int {
        var low = startIndex, high = endIndex
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(range(self[middle])) <= location { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// One Match's pill: its range in the Input and its Pattern's color.
struct Pill: Equatable {
    var range: NSRange
    var color: PatternColor
    /// Hover or the Inspector's selection: the strong tint.
    var isStrong: Bool
    /// The Inspector's selection: a ring in the solid color.
    var hasRing: Bool

    var fill: NSColor { NSColor.pattern(color, isStrong ? \.strongTint : \.tint) }
}

/// Draws the Input's pills behind its text. A pill that wraps is one shape across
/// its lines: the pieces on neighbouring lines join over the gap between them,
/// with rounded corners inside and out, as a text selection highlight does.
final class PillLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Space between lines, so 13 pt text sits on a 1.75 line height and pills on
    /// neighbouring lines don't touch.
    static let lineSpacing: CGFloat = 7

    /// The pills in drawing order: the Matches' by position (top-level Matches don't
    /// overlap), then at most one with a ring. The text view redraws after setting them.
    var pills: [Pill] = []
    /// The selected entry's range; its text selection isn't filled, since the ring shows it.
    var ringedRange: NSRange? { pills.last?.hasRing == true ? pills.last?.range : nil }
    /// Pills fading in, drawn at `fadeProgress` of their opacity.
    var fadingRanges: Set<NSRange> = []
    var fadeProgress: CGFloat = 1
    /// Told of each edit to the text, once this layout manager has taken it in.
    var onEdit: (@MainActor (TextEdit) -> Void)?

    /// The pills by position, without the ringed one.
    private var pillsByPosition: ArraySlice<Pill> { pills.dropLast(ringedRange == nil ? 0 : 1) }

    /// The pills over any of `characters`, in drawing order.
    func pills(overlapping characters: NSRange) -> [Pill] {
        var found: [Pill] = []
        let byPosition = pillsByPosition
        var index = byPosition.firstIndex(endingAfter: characters.location, range: \.range)
        while index < byPosition.endIndex, byPosition[index].range.location < NSMaxRange(characters) {
            found.append(byPosition[index])
            index += 1
        }
        if let ringed = pills.last, ringed.hasRing, NSIntersectionRange(ringed.range, characters).length > 0 {
            found.append(ringed)
        }
        return found
    }

    /// Deepens or lightens the Match's pill at `range`, redrawing just it. The ringed
    /// pill is always strong.
    func setStrong(_ isStrong: Bool, forPillAt range: NSRange) {
        let byPosition = pillsByPosition
        let index = byPosition.firstIndex(endingAfter: range.location, range: \.range)
        guard index < byPosition.endIndex, pills[index].range == range, pills[index].isStrong != isStrong else { return }
        pills[index].isStrong = isStrong
        invalidateDisplay(forCharacterRange: range)
    }

    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
        changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(
            for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
            invalidatedRange: invalidatedCharRange
        )
        guard editMask.contains(.editedCharacters), let onEdit else { return }
        let edit = TextEdit(range: newCharRange, delta: delta)
        MainActor.assumeIsolated { onEdit(edit) }
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, lineSpacingAfterGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: NSRect
    ) -> CGFloat {
        Self.lineSpacing
    }

    /// The pieces of a pill: per line, the text it covers there, 3 pt wider each
    /// side and 1.5 pt taller each way than the line's text.
    func pieces(of range: NSRange) -> [NSRect] {
        pieces(ofGlyphs: glyphRange(forCharacterRange: range, actualCharacterRange: nil))
    }

    /// The characters a line's piece ends before: a space a line wraps at, or any
    /// line break (CR, LF, NEL, the Unicode line and paragraph separators).
    private static let trailingBreaks: Set<unichar> = [10, 13, 32, 0x85, 0x2028, 0x2029]

    private func pieces(ofGlyphs glyphs: NSRange) -> [NSRect] {
        guard let container = textContainers.first, let string = textStorage?.string as NSString? else { return [] }
        var pieces: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, lineGlyphs, _ in
            var covered = NSIntersectionRange(lineGlyphs, glyphs)
            // The space or line break a line wraps at isn't part of the piece.
            while covered.length > 0,
                  Self.trailingBreaks.contains(string.character(at: self.characterIndexForGlyph(at: NSMaxRange(covered) - 1))) {
                covered.length -= 1
            }
            guard covered.length > 0 else { return }
            let text = self.boundingRect(forGlyphRange: covered, in: container)
            pieces.append(NSRect(
                x: text.minX - 3, y: used.minY - 1.5, width: text.width + 6, height: used.height - Self.lineSpacing + 3
            ))
        }
        return pieces
    }

    /// The shapes a pill draws as: its pieces, joined where neighbouring lines' pieces
    /// overlap.
    func shapes(of range: NSRange) -> [NSBezierPath] {
        Self.shapes(joining: pieces(of: range))
    }

    /// The shapes of the pill over `range`, as far as they show over `glyphsToShow`:
    /// built from the lines shown and one either side, which is all the outline there
    /// depends on (each join, straight edge and corner depends only on neighbouring
    /// lines), so a redraw of a few lines doesn't outline a pill thousands of lines long.
    func shapes(of range: NSRange, around glyphsToShow: NSRange) -> [NSBezierPath] {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let shown = NSIntersectionRange(glyphs, glyphsToShow)
        guard shown.length > 0 else { return [] }
        var line = NSRange()
        lineFragmentRect(forGlyphAt: shown.location, effectiveRange: &line)
        if line.location > glyphs.location { lineFragmentRect(forGlyphAt: line.location - 1, effectiveRange: &line) }
        let start = max(glyphs.location, line.location)
        lineFragmentRect(forGlyphAt: NSMaxRange(shown) - 1, effectiveRange: &line)
        if NSMaxRange(line) < NSMaxRange(glyphs) { lineFragmentRect(forGlyphAt: NSMaxRange(line), effectiveRange: &line) }
        let end = min(NSMaxRange(glyphs), NSMaxRange(line))
        return Self.shapes(joining: pieces(ofGlyphs: NSRange(location: start, length: end - start)))
    }

    static let cornerRadius: CGFloat = 5

    /// `pieces`, top to bottom, as shapes: each run of pieces that overlap the one
    /// above by at least two corners' width is one outline; the rest stand alone.
    /// Joining pieces that barely overlap would pinch the shape to a sliver.
    static func shapes(joining pieces: [NSRect], radius: CGFloat = cornerRadius) -> [NSBezierPath] {
        var runs: [[NSRect]] = []
        for piece in pieces {
            if let above = runs.last?.last, piece.minY > above.minY,
               min(above.maxX, piece.maxX) - max(above.minX, piece.minX) >= 2 * radius {
                runs[runs.count - 1].append(piece)
            } else {
                runs.append([piece])
            }
        }
        return runs.map { outline(of: $0, radius: radius) }
    }

    private static func outline(of run: [NSRect], radius: CGFloat) -> NSBezierPath {
        guard run.count > 1 else { return NSBezierPath(roundedRect: run[0], xRadius: radius, yRadius: radius) }
        // Neighbours meet halfway across the gap between their lines.
        var rects = run
        for index in rects.indices.dropLast() {
            let middle = (rects[index].maxY + rects[index + 1].minY) / 2
            rects[index].size.height = middle - rects[index].minY
            rects[index + 1].size.height = rects[index + 1].maxY - middle
            rects[index + 1].origin.y = middle
        }
        // Down the right edges, back up the left ones.
        var corners: [NSPoint] = []
        for rect in rects {
            corners += [NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.maxY)]
        }
        for rect in rects.reversed() {
            corners += [NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.minY)]
        }
        return roundedPolygon(withoutStraightPoints(corners), radius: radius)
    }

    /// `corners` less repeated points and points midway along a straight edge, as
    /// where neighbouring lines' pieces end level. One pass: each point drops the
    /// straight points before it, then the ends are checked where they meet.
    private static func withoutStraightPoints(_ corners: [NSPoint]) -> [NSPoint] {
        func isStraight(_ previous: NSPoint, _ point: NSPoint, _ next: NSPoint) -> Bool {
            abs((point.x - previous.x) * (next.y - point.y) - (point.y - previous.y) * (next.x - point.x)) < 0.01
        }
        var points: [NSPoint] = []
        points.reserveCapacity(corners.count)
        for corner in corners {
            while points.count >= 2, isStraight(points[points.count - 2], points[points.count - 1], corner) {
                points.removeLast()
            }
            points.append(corner)
        }
        var first = 0
        while points.count - first > 3 {
            if isStraight(points[points.count - 2], points[points.count - 1], points[first]) {
                points.removeLast()
            } else if isStraight(points[points.count - 1], points[first], points[first + 1]) {
                first += 1
            } else {
                break
            }
        }
        return Array(points[first...])
    }

    /// The polygon through `points` with each corner rounded, by up to `radius`
    /// (less where an edge is too short for it).
    private static func roundedPolygon(_ points: [NSPoint], radius: CGFloat) -> NSBezierPath {
        func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
        let path = NSBezierPath()
        let count = points.count
        guard let last = points.last, let first = points.first else { return path }
        path.move(to: NSPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in points.indices {
            let previous = points[(index + count - 1) % count]
            let point = points[index], next = points[(index + 1) % count]
            let corner = min(radius, distance(previous, point) / 2, distance(point, next) / 2)
            path.appendArc(from: point, to: next, radius: corner)
        }
        path.close()
        return path
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for pill in pills(overlapping: characters) {
            let opacity = fadingRanges.contains(pill.range) ? fadeProgress : 1
            for shape in shapes(of: pill.range, around: glyphsToShow) {
                shape.transform(using: AffineTransform(translationByX: origin.x, byY: origin.y))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(opacity)
                pill.fill.setFill()
                shape.fill()
                if pill.hasRing {
                    // A 1.5 pt ring inside the edge: twice that, clipped to the shape.
                    shape.addClip()
                    shape.lineWidth = 3
                    NSColor.pattern(pill.color, \.solid).setStroke()
                    shape.stroke()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor
    ) {
        if charRange == ringedRange { return }
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }
}
