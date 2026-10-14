import AppKit
import TextierCore

/// Go to Line: a small field floating over the top of a text view, as VS Code's
/// is. It takes a line, or a line and column (`LineTarget`); Return moves the
/// cursor there, scrolls the line to the middle and flashes it; Esc, or the field
/// losing the keyboard, closes it. Lines are counted as the line numbers count
/// them: a wrapped line is one.
@MainActor
final class GoToLineBar: NSObject, NSTextFieldDelegate {
    /// The bar showing, at most one.
    private(set) static var current: GoToLineBar?

    let field = NSTextField()
    /// The bar: a rounded, shadowed card in the window's colors, an icon, the field.
    private let box = NSView()
    private let icon = NSImageView()
    private weak var textView: NSTextView?
    /// Where each line of the text starts, as when the bar opened.
    private let lineStarts: [Int]
    private var isClosing = false

    /// Opens the bar over `textView`, closing any other.
    static func show(for textView: NSTextView) {
        current?.close()
        guard let window = textView.window, let content = window.contentView, let scrollView = textView.enclosingScrollView
        else { return }
        let bar = GoToLineBar(textView: textView)
        current = bar
        bar.attach(over: scrollView, in: content)
        window.makeFirstResponder(bar.field)
    }

    private init(textView: NSTextView) {
        self.textView = textView
        lineStarts = LineNumberRuler.lineStarts(in: textView.string as NSString)
        super.init()
        let count = lineStarts.count.formatted()
        field.placeholderString = "Go to line (1–\(count)), or line:column"
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.setAccessibilityLabel("Go to line")
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.shadowOpacity = 0.35
        box.layer?.shadowRadius = 14
        box.layer?.shadowOffset = CGSize(width: 0, height: -4)
        updateColors()
        icon.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        box.addSubview(icon)
        box.addSubview(field)
    }

    /// Floats the bar centered at the top of `scrollView`, in the window's content
    /// view (the Input sits in a split view, which would take it for a pane).
    private func attach(over scrollView: NSScrollView, in content: NSView) {
        let frame = scrollView.convert(scrollView.bounds, to: content)
        let size = NSSize(width: min(380, frame.width - 24), height: 36)
        let top = content.isFlipped ? frame.minY + 10 : frame.maxY - 10 - size.height
        box.frame = NSRect(x: frame.midX - size.width / 2, y: top, width: size.width, height: size.height)
        box.autoresizingMask = content.isFlipped ? [.minXMargin, .maxXMargin, .maxYMargin] : [.minXMargin, .maxXMargin, .minYMargin]
        icon.frame = NSRect(x: 12, y: 10, width: 16, height: 16)
        field.frame = NSRect(x: 34, y: 9, width: size.width - 46, height: 18)
        content.addSubview(box)
        updateColors()
    }

    /// Moves the cursor to what the field says, or beeps when it isn't a line.
    func go() {
        guard let target = LineTarget(field.stringValue), let textView else {
            NSSound.beep()
            return
        }
        let text = textView.string as NSString
        var location = target.location(lineStarts: lineStarts, length: text.length)
        // A line ending in CR LF ends before the CR, not between the two.
        if location > 0, location < text.length, text.character(at: location) == 0x0A,
           text.character(at: location - 1) == 0x0D { location -= 1 }
        close()
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        center(location, in: textView)
        // The line flashes, without its line break.
        var line = text.lineRange(for: NSRange(location: location, length: 0))
        while line.length > 0, [0x0A, 0x0D].contains(text.character(at: NSMaxRange(line) - 1)) { line.length -= 1 }
        if line.length > 0 { textView.showFindIndicator(for: line) }
    }

    /// Scrolls `textView` so the line at `location` is in the middle of its view.
    private func center(_ location: Int, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let scrollView = textView.enclosingScrollView,
              (textView.string as NSString).length > 0 else {
            return textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(location, max(0, (textView.string as NSString).length - 1)))
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let clip = scrollView.contentView
        let y = line.midY + textView.textContainerOrigin.y - clip.bounds.height / 2
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The card's fill, edge and shadow for the window's appearance (layers don't
    /// follow it by themselves).
    private func updateColors() {
        (box.window?.effectiveAppearance ?? textView?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            box.layer?.borderColor = NSColor.separatorColor.cgColor
            box.layer?.shadowColor = NSColor.shadowColor.cgColor
        }
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        box.removeFromSuperview()
        if Self.current === self { Self.current = nil }
    }

    // MARK: The field

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            go()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            self.textView?.window?.makeFirstResponder(self.textView)
            return true
        default:
            return false
        }
    }

    /// What isn't a line yet shows in red.
    func controlTextDidChange(_ notification: Notification) {
        let text = field.stringValue
        field.textColor = text.isEmpty || LineTarget(text) != nil ? .labelColor : .systemRed
    }

    /// The keyboard went elsewhere: the bar closes.
    func controlTextDidEndEditing(_ notification: Notification) {
        close()
    }
}
