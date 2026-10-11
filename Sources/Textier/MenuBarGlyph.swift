import AppKit

/// textier's menu bar icon, Glyph A of the icon designs ("Marked lines"): lines of
/// text on an 18 pt grid, one word a filled pill and one an outlined pill, as the
/// Input marks its Matches. A template image, so macOS tints it for a light or
/// dark menu bar and for pressed.
enum MenuBarGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            func pill(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> NSBezierPath {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
            }
            pill(2, 3, 6.5, 4, radius: 1.4).fill()
            pill(10.5, 4.3, 5.5, 1.4, radius: 0.7).fill()
            pill(2, 8.3, 14, 1.4, radius: 0.7).fill()
            pill(2, 12.3, 3.5, 1.4, radius: 0.7).fill()
            let outlined = pill(7.6, 11.1, 8.4, 3.8, radius: 1.3)
            outlined.lineWidth = 1.2
            outlined.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "textier"
        return image
    }()
}
