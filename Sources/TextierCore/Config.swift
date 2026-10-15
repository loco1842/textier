/// The ordered Patterns textier detects with, the user's own Grok Definitions,
/// the global shortcut, the editor command template, the Inspector's layout,
/// whether the app is light or dark, when the Selection Popover forgets its text,
/// and whether textier looks for updates by itself.
public struct Config: Sendable, Equatable {
    public var patterns: [Pattern]
    /// The user's own Grok Definitions, in file order. Each replaces a bundled one
    /// of the same name everywhere, inside other bundled definitions too.
    public var grok: [GrokDefinition]
    public var shortcut: Shortcut
    /// The `open-file` command template with `{path}` and `{line}` placeholders;
    /// nil when unset, so the editor is resolved from `$EDITOR` instead.
    public var editorCommand: String?
    /// How the Inspector groups Matches by Pattern.
    public var inspectorLayout: InspectorLayout
    /// Light, dark, or following the system. The JSON Viewer colors with GitHub
    /// Light or Dark to match.
    public var appearance: AppearanceSetting
    /// Seconds after the Selection Popover closes that it clears its text; 0 keeps
    /// it until the next selection.
    public var clearSelectionAfter: Int
    /// The app's own shortcuts (the global one is `shortcut`).
    public var shortcuts: CommandShortcuts
    /// Whether textier looks for a newer release at launch and once a day.
    public var checkForUpdates: Bool

    public init(
        patterns: [Pattern], grok: [GrokDefinition] = [], shortcut: Shortcut = .default, editorCommand: String? = nil,
        inspectorLayout: InspectorLayout = .tabs, appearance: AppearanceSetting = .system,
        clearSelectionAfter: Int = 0, shortcuts: CommandShortcuts = .default, checkForUpdates: Bool = true
    ) {
        self.patterns = patterns
        self.grok = grok
        self.shortcut = shortcut
        self.editorCommand = editorCommand
        self.inspectorLayout = inspectorLayout
        self.appearance = appearance
        self.clearSelectionAfter = clearSelectionAfter
        self.shortcuts = shortcuts
        self.checkForUpdates = checkForUpdates
    }

    public static let `default` = Config(patterns: Pattern.shipped)

    /// The `escaped-json` Pattern, when it's in the Config and enabled. A config
    /// file without the entry has it off, like any Pattern it doesn't list.
    public var escapedJSONPattern: Pattern? {
        patterns.first { $0.kind == .builtin(.escapedJSON) && $0.enabled }
    }

    /// The Pattern that found `match`, when `match` came from this Config.
    public func pattern(of match: Match) -> Pattern? {
        patterns.indices.contains(match.patternIndex) ? patterns[match.patternIndex] : nil
    }
}

/// How the Inspector shows its Pattern groups. The config file names it by the
/// raw value.
public enum InspectorLayout: String, Sendable, Equatable, CaseIterable {
    /// One tab per Pattern; the selected tab's Matches are listed.
    case tabs
    /// One list with a collapsible section per Pattern, for Inputs small enough
    /// to take in at once.
    case list
}

/// Whether textier is light or dark: like the system, or always one. The config
/// file names it by the raw value.
public enum AppearanceSetting: String, Sendable, Equatable, CaseIterable {
    case system
    case light
    case dark
}
