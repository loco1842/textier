import Foundation

/// A command in the app with a keyboard shortcut the user can change.
public enum ShortcutCommand: String, Sendable, CaseIterable {
    case toggleHighlighting
    case switchInspectorLayout
    case popOut
    case goToLine
    case toggleWrapLines
    case settings
    case quit

    /// Its name in Settings.
    public var title: String {
        switch self {
        case .toggleHighlighting: "Toggle Highlighting"
        case .switchInspectorLayout: "Switch Inspector Layout"
        case .popOut: "Pop Out"
        case .goToLine: "Go to Line"
        case .toggleWrapLines: "Toggle Wrap Lines"
        case .settings: "Settings"
        case .quit: "Quit"
        }
    }

    /// Its shortcut until the user changes it; nil for none.
    public var defaultShortcut: Shortcut? {
        switch self {
        case .toggleHighlighting: Shortcut("cmd+e")
        case .switchInspectorLayout: Shortcut("cmd+l")
        case .popOut: Shortcut("cmd+shift+p")
        case .goToLine: Shortcut("cmd+g")
        case .toggleWrapLines: nil
        case .settings: Shortcut("cmd+,")
        case .quit: Shortcut("cmd+q")
        }
    }
}

/// The app's own keyboard shortcuts: one for each command (or none), the
/// modifiers that with a digit select the Inspector's tabs, and the modifiers
/// that make a click on a Match select it. The global shortcut is the Config's
/// `shortcut`.
public struct CommandShortcuts: Sendable, Equatable {
    /// The commands that have a shortcut; one that's missing has none.
    public var assigned: [ShortcutCommand: Shortcut]
    /// With 1–9: the Inspector's first nine tabs.
    public var selectTab: Shortcut.Modifiers
    /// With a click on a Match: selects it in the Inspector.
    public var matchClick: Shortcut.Modifiers

    public init(assigned: [ShortcutCommand: Shortcut], selectTab: Shortcut.Modifiers, matchClick: Shortcut.Modifiers) {
        self.assigned = assigned
        self.selectTab = selectTab
        self.matchClick = matchClick
    }

    public static let `default` = CommandShortcuts(
        assigned: ShortcutCommand.allCases.reduce(into: [:]) { $0[$1] = $1.defaultShortcut },
        selectTab: [.command], matchClick: [.command]
    )

    public subscript(command: ShortcutCommand) -> Shortcut? {
        get { assigned[command] }
        set { assigned[command] = newValue }
    }

    /// The command `shortcut` runs, if any.
    public func command(for shortcut: Shortcut) -> ShortcutCommand? {
        ShortcutCommand.allCases.first { assigned[$0] == shortcut }
    }

    /// Text editing's own shortcuts, which no command may take.
    public static let reserved: [Shortcut] = ["cmd+c", "cmd+v", "cmd+x", "cmd+z", "cmd+shift+z", "cmd+a"]
        .compactMap(Shortcut.init)

    /// Why `shortcut` can't be `command`'s, given the others and the global
    /// `shortcut`; nil when it can.
    public func problem(with shortcut: Shortcut, for command: ShortcutCommand, global: Shortcut) -> String? {
        if Self.reserved.contains(shortcut) { return "\(shortcut.symbolText) is for editing text" }
        if shortcut == global { return "\(shortcut.symbolText) is the shortcut that opens the Selection Popover" }
        if let other = self.command(for: shortcut), other != command { return "\(shortcut.symbolText) is already \(other.title)" }
        if shortcut.modifiers == selectTab, ("1"..."9").contains(shortcut.key), shortcut.key.count == 1 {
            return "\(shortcut.symbolText) selects tab \(shortcut.key)"
        }
        return nil
    }
}

extension Shortcut {
    /// How macOS menus write it: ⌃⌥T, ⌘, , ⇧⌘P.
    public var symbolText: String {
        Self.symbols(of: modifiers) + (key == "space" ? "Space" : key.uppercased())
    }

    /// ⌃⌥⇧⌘, in macOS's order.
    public static func symbols(of modifiers: Modifiers) -> String {
        [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }.map(\.1).joined()
    }
}
