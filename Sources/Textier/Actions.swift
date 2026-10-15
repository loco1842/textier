import AppKit
import SwiftUI
import TextierCore

extension Action {
    var title: String {
        switch self {
        case .copy: "Copy"
        // The same Match Window the Action bar's Pop Out opens, so the same name.
        case .open: "Pop Out"
        case .copyPretty: "Copy Beautified"
        case .openURL: "Open in Browser"
        case .openFile: "Open in Editor"
        }
    }

    /// Runs the Action on an Inspector entry. `patternName` titles the Match Window
    /// that `open` shows.
    @MainActor
    func perform(on entry: InspectorEntry, patternName: String) {
        switch self {
        case .copy:
            copyToPasteboard(entry.text)
        case .open:
            MatchWindowController.open(entry, patternName: patternName)
        case .copyPretty:
            copyToPasteboard(entry.prettyText)
        case .openURL:
            if let url = URL(string: entry.text) { Effects.openURL(url) }
        case .openFile:
            let location = entry.fileLocation
            Effects.openFile(location.path, location.line)
        }
    }

    /// Runs the Action on a Match found outside the Inspector (a URL or file path
    /// value in the JSON Viewer). `pairedLine` is the line a file path value takes
    /// from its sibling `line` key.
    @MainActor
    func perform(on match: Match, pairedLine: Int? = nil) {
        switch self {
        case .open:
            MatchWindowController.open(text: match.text, patternName: match.patternName, actions: match.actions)
        case .openFile:
            let location = FileLocation(matchText: match.text, homeDirectory: NSHomeDirectory())
            Effects.openFile(location.path, location.line ?? pairedLine)
        default:
            perform(on: InspectorEntry(wholeText: match.text, actions: match.actions), patternName: match.patternName)
        }
    }
}

extension InspectorEntry {
    /// An entry standing for the whole of `text`, for running Actions on text the
    /// Inspector didn't list.
    init(wholeText text: String, actions: [Action]) {
        self.init(
            index: 0, preview: InspectorEntry.preview(of: text), range: NSRange(text.startIndex..., in: text), text: text, actions: actions,
            parent: nil, detail: .text(text)
        )
    }

    /// Where a file path entry points: its parsed location, paired line included,
    /// or else its text read as a path.
    var fileLocation: FileLocation {
        if case .filePath(let file) = detail { return FileLocation(path: file.path, line: file.line, column: file.column) }
        return FileLocation(matchText: text, homeDirectory: NSHomeDirectory())
    }

    /// A file path that takes its line from its JSON object's `line` key, as logged
    /// plus `:line`; nil for anything else.
    var pathWithLine: String? {
        guard case .filePath(let file) = detail, file.lineSource == .lineKey, let line = file.line else { return nil }
        return "\(text):\(line)"
    }

    var isJSON: Bool {
        if case .json = detail { true } else { false }
    }

    /// The entry's JSON beautified, or its text when it isn't JSON.
    var prettyText: String {
        if case .json(let value) = detail { return value.prettyPrinted }
        return JSONValue.container(from: text)?.prettyPrinted ?? text
    }

    /// The buttons of the entry's Action bar: its Actions in order, then Copy
    /// Beautified (JSON) and Copy when they lack them, then Copy with Line on a
    /// paired file path, then Pop Out unless the `open` Action (also Pop Out) is there
    /// (both bar fixtures, not Actions). Plain Text offers only Copy, and a Match
    /// Window offers nothing that would open it again.
    func barItems(isPlainText: Bool, inMatchWindow: Bool) -> [ActionBarItem] {
        guard !isPlainText else { return [.action(.copy)] }
        let actions = inMatchWindow ? actions.filter { $0 != .open } : actions
        var items = actions.map(ActionBarItem.action)
        if case .json = detail, !actions.contains(.copyPretty) { items.append(.action(.copyPretty)) }
        if !actions.contains(.copy) { items.append(.action(.copy)) }
        if pathWithLine != nil { items.append(.copyWithLine) }
        if !inMatchWindow, !actions.contains(.open) { items.append(.popOut) }
        return items
    }
}

extension FieldEntry {
    /// The buttons beside a Field's row: its link's Actions, but Copy, which a
    /// click on the row does.
    var linkActions: [Action] {
        link?.actions.filter { $0 != .copy } ?? []
    }

    /// A click on the row.
    @MainActor
    func copy() {
        copyToPasteboard(field.value)
    }
}

/// One button of an Action bar.
enum ActionBarItem: Hashable {
    case action(Action)
    case popOut
    /// Copies a paired file path as `path:line` (`pathWithLine`).
    case copyWithLine

    var title: String {
        switch self {
        case .action(let action): action.title
        case .popOut: "Pop Out"
        case .copyWithLine: "Copy with Line"
        }
    }
}

/// Where Actions reach outside textier: the pasteboard, the browser and the
/// editor. The app tests swap them for recorders.
@MainActor
enum Effects {
    static var pasteboard = NSPasteboard.general
    static var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Opens a file in the editor, at the line when there is one.
    static var openFile: (_ path: String, _ line: Int?) -> Void = { Editor.open(path: $0, line: $1) }
    /// Where a file goes when the editor can't open it (`Editor.openWithoutEditor`):
    /// its default app, or Finder.
    static var openWithDefaultApp: (URL) -> Void = { NSWorkspace.shared.open($0) }
    static var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Brings textier forward with `window` in front and key. The app tests show
    /// their windows without taking the screen or the keyboard from the person
    /// working while they run.
    static var present: (NSWindow) -> Void = { window in
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    /// Shows `window` in front without bringing textier forward, so it doesn't take
    /// the keyboard from what the person is typing in: for a window textier opens
    /// by itself, such as an update found by the daily check.
    static var presentInBackground: (NSWindow) -> Void = { window in
        window.orderFrontRegardless()
    }
    /// Where the "Copied" label goes: by the mouse pointer. The app tests put it off
    /// screen, so a run doesn't flash it by the pointer of whoever is working.
    static var copiedLabelOrigin: () -> NSPoint = {
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x + 12, y: mouse.y + 8)
    }
}

/// Puts `string` on the pasteboard and briefly says so.
@MainActor
func copyToPasteboard(_ string: String) {
    Effects.pasteboard.clearContents()
    Effects.pasteboard.setString(string, forType: .string)
    noteOwnCopy()
    CopiedHUD.show()
}

/// Records that textier just wrote the pasteboard. After the write: clearing it
/// moves the count too.
@MainActor
func noteOwnCopy() {
    lastOwnCopy = Effects.pasteboard.changeCount
}

/// A text view whose Copy and Cut count as textier's own copies, so selecting text
/// and pressing ⌘C in it doesn't read as someone else's copy (see `lastOwnCopy`).
/// Copy writes `Effects.pasteboard`, the general pasteboard outside the app tests.
@MainActor
class OwnCopyTextView: NSTextView {
    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        writeSelection(to: Effects.pasteboard, types: writablePasteboardTypes)
        noteOwnCopy()
    }

    override func cut(_ sender: Any?) {
        super.cut(sender)
        noteOwnCopy()
    }
}

/// The pasteboard's change count just after textier's own last copy, so
/// `SelectionCapture`, watching for a late ⌘C, doesn't take a copy made in
/// textier for one and put the clipboard back over it.
@MainActor
private(set) var lastOwnCopy: Int?

/// The brief "Copied" confirmation: a small label by the mouse pointer that fades
/// in and out (or just comes and goes, under Reduce Motion).
@MainActor
enum CopiedHUD {
    private(set) static var panel: NSPanel?
    /// The fade under way, or the wait before fading out. A run loop timer, so a
    /// new copy can stop it outright (an AppKit window animation can't be), and so
    /// it also runs while the app tests hold the main queue.
    private static var timer: Timer?

    static func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(Effects.copiedLabelOrigin())
        // A quick second copy fades up from wherever the first one's fade left it.
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fade(panel, to: 1, over: 0.15) {
            schedule(after: 0.9) {
                fade(panel, to: 0, over: 0.25) { panel.orderOut(nil) }
            }
        }
    }

    /// Takes `panel`'s alpha to `target` over `duration` (at once under Reduce
    /// Motion), then runs `then`.
    private static func fade(_ panel: NSPanel, to target: CGFloat, over duration: TimeInterval, then: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        let from = panel.alphaValue
        guard !Motion.isReduced, from != target else {
            panel.alphaValue = target
            return then()
        }
        let start = Date()
        let fade = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let progress = min(1, Date().timeIntervalSince(start) / duration)
                panel.alphaValue = from + (target - from) * progress
                guard progress >= 1 else { return }
                timer?.invalidate()
                then()
            }
        }
        RunLoop.main.add(fade, forMode: .common)
        timer = fade
    }

    private static func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        let wait = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(wait, forMode: .common)
        timer = wait
    }

    private static func makePanel() -> NSPanel {
        let label = NSHostingView(rootView: Text("Copied")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .fixedSize())
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: label.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = label
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}
