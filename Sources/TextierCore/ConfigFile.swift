import Foundation

/// Something wrong in the config file. A fatal warning means the file couldn't be
/// used at all; any other warning means one entry was skipped and the rest loaded.
public struct ConfigWarning: Sendable, Equatable {
    public var message: String
    public var isFatal: Bool

    public init(_ message: String, isFatal: Bool = false) {
        self.message = message
        self.isFatal = isFatal
    }
}

/// The result of reading a config file: a Config (nil when the file is unusable),
/// the warnings found on the way, and the entries skipped for them.
public struct ConfigLoad: Sendable, Equatable {
    public var config: Config?
    public var warnings: [ConfigWarning]
    public var skipped: SkippedEntries

    public init(config: Config?, warnings: [ConfigWarning], skipped: SkippedEntries = SkippedEntries()) {
        self.config = config
        self.warnings = warnings
        self.skipped = skipped
    }
}

/// The Pattern and Grok Definition entries a config file has but couldn't load,
/// as written, so writing the file back (from Settings) keeps one the user is
/// still fixing by hand where it was.
public struct SkippedEntries: Sendable, Equatable {
    public var patterns: [Skipped<JSONValue>]
    public var grok: [Skipped<JSONEntry>]

    public init(patterns: [Skipped<JSONValue>] = [], grok: [Skipped<JSONEntry>] = []) {
        self.patterns = patterns
        self.grok = grok
    }

    /// An entry and its place among its list's entries in the file.
    public struct Skipped<Entry: Sendable & Equatable>: Sendable, Equatable {
        public var position: Int
        public var entry: Entry

        public init(position: Int, entry: Entry) {
            self.position = position
            self.entry = entry
        }
    }
}

/// The config file, `~/.config/textier/config.json`:
///
/// ```json
/// {
///   "shortcut": "ctrl+option+t",
///   "editorCommand": "",
///   "inspectorLayout": "tabs",
///   "appearance": "system",
///   "clearSelectionAfter": 0,
///   "shortcuts": { "toggleHighlighting": "cmd+e", "goToLine": "cmd+g", "toggleWrapLines": "", …,
///                  "selectTab": "cmd", "matchClick": "cmd" },
///   "patterns": [
///     { "name": "json", "builtin": "json", "enabled": true, "actions": ["open", "copy-pretty", "copy"] },
///     { "name": "url", "regex": "…", "enabled": true, "actions": ["open-url", "copy"], "color": "#0969da" },
///     { "name": "ticket", "regex": "%{MYTICKET:key}", "actions": ["copy"], "color": { "light": "#9a6700", "dark": "#e3b341" } },
///     { "name": "status", "regex": "\\b[1-5]\\d\\d\\b", "actions": ["copy"],
///       "colors": [{ "when": "^5", "color": "#e5484d" }, { "when": "^4", "color": "#ef5f00" }] }
///   ],
///   "grok": { "MYTICKET": "[A-Z]+-\\d+" }
/// }
/// ```
///
/// Pattern order is Config order. Patterns can share a `name`, but `json` and
/// `escaped-json` are reserved for those Built-in Patterns. Each entry has a `name`, exactly one of `regex`
/// (a Preset or User Pattern) or `builtin` (a `BuiltinID` raw value), an
/// `actions` list (first is the default Action), and optionally `enabled`
/// (default true), `color` (one hex value or a light/dark pair; without one the
/// Pattern takes its palette color) and `colors`, its Color Rules: a list of
/// `{ "when": regex, "color": color }`, the first whose regex is in a Match's text
/// (ignoring case) coloring it (without the key a shipped Pattern takes its default
/// rules; `[]` turns them off); a rule that can't be used is skipped with a
/// warning, and writing the file keeps it as written, as it keeps a `colors` that
/// isn't a list, which is ignored with a warning. A Preset whose `regex` is
/// one an earlier textier shipped for it takes the one it ships now.
/// `shortcut` uses the `Shortcut` string format and defaults to ⌃⌥T; an empty or
/// missing `editorCommand` means unset. `inspectorLayout` an
/// `InspectorLayout` raw value, `tabs` by default; `appearance` an `AppearanceSetting`
/// raw value, `system` by default. `clearSelectionAfter` is how many seconds after
/// the Selection Popover closes it clears its text, a whole number; 0 (the
/// default) keeps it. `shortcuts` holds the app's own shortcuts by `ShortcutCommand`
/// raw value, each in the `Shortcut` format, `""` for none and a missing one at its
/// default; `selectTab` and `matchClick` are modifiers alone (`"cmd"`), which with a
/// digit select a tab and with a click select a Match. A shortcut that doesn't read
/// keeps its default; one text editing uses, the global shortcut or one a command
/// before it has is left unassigned; each with a warning. A `theme` key, which named VS Code theme files
/// once, is ignored with a warning.
/// `grok` maps the user's own Grok Definition names to regex bodies, each replacing
/// a bundled definition of the same name; a broken one is skipped with a warning,
/// and so are the Patterns that use it. The file is read with textier's own JSON parser (ADR-0002).
public enum ConfigFile {
    public static var defaultLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/textier/config.json")
    }

    /// Writes `Config.default` to `url`, creating its directory, unless a file is
    /// already there. Returns whether it wrote.
    @discardableResult
    public static func writeDefaultIfAbsent(at url: URL) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(.default).write(to: url, options: .atomic)
        return true
    }

    // MARK: Writing

    /// The file text for `config`: pretty-printed, keys in the documented order,
    /// every field written so the file documents itself. `skipped` entries go back
    /// to their places, as written.
    public static func encode(_ config: Config, keeping skipped: SkippedEntries = SkippedEntries()) -> Data {
        let patterns = merge(config.patterns.map(entry), skipped.patterns.map { ($0.position, raw($0.entry)) })
            .joined(separator: ",\n")
        let text = """
        {
          "shortcut": \(quote(config.shortcut.description)),
          "editorCommand": \(quote(config.editorCommand ?? "")),
          "inspectorLayout": \(quote(config.inspectorLayout.rawValue)),
          "appearance": \(quote(config.appearance.rawValue)),
          "clearSelectionAfter": \(config.clearSelectionAfter),
          "shortcuts": \(shortcutsObject(config.shortcuts)),
          "patterns": [
        \(patterns)
          ],
          "grok": \(grokObject(config.grok, keeping: skipped.grok))
        }

        """
        return Data(text.utf8)
    }

    /// The `grok` object, one definition per line in Config order.
    private static func grokObject(_ grok: [GrokDefinition], keeping skipped: [SkippedEntries.Skipped<JSONEntry>]) -> String {
        let lines = merge(
            grok.map { "    \(quote($0.name)): \(quote($0.regex))" },
            skipped.map { ($0.position, "    \(quote($0.entry.key)): " + indented($0.entry.value.prettyPrinted)) }
        )
        return lines.isEmpty ? "{}" : "{\n" + lines.joined(separator: ",\n") + "\n  }"
    }

    /// `lines` with each of `inserted` put back at its position, in position order.
    private static func merge(_ lines: [String], _ inserted: [(position: Int, line: String)]) -> [String] {
        var lines = lines
        for (position, line) in inserted.sorted(by: { $0.position < $1.position }) {
            lines.insert(line, at: min(position, lines.count))
        }
        return lines
    }

    /// A skipped Pattern entry as written, at the depth of the others.
    private static func raw(_ value: JSONValue) -> String {
        "    " + indented(value.prettyPrinted)
    }

    /// Indents every line but the first to sit inside the `patterns` or `grok` list.
    private static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n    ")
    }

    private static func entry(_ pattern: Pattern) -> String {
        var fields = [#""name": \#(quote(pattern.name))"#]
        switch pattern.kind {
        case .regex(let source): fields.append(#""regex": \#(quote(source))"#)
        case .builtin(let builtin): fields.append(#""builtin": \#(quote(builtin.rawValue))"#)
        }
        fields.append(#""enabled": \#(pattern.enabled)"#)
        fields.append(#""actions": [\#(pattern.actions.map { quote($0.rawValue) }.joined(separator: ", "))]"#)
        if let color = pattern.color {
            fields.append(#""color": \#(colorValue(color))"#)
        }
        if let rules = pattern.colorRules {
            let written = merge(
                rules.map { rule in #"{ "when": \#(quote(rule.when)), "color": \#(colorValue(rule.color)) }"# },
                pattern.skippedColorRules.map { ($0.position, oneLine($0.entry)) }
            )
            fields.append(written.isEmpty ? #""colors": []"# : "\"colors\": [\n        " + written.joined(separator: ",\n        ") + "\n      ]")
        } else if let colors = pattern.skippedColors {
            fields.append(#""colors": \#(oneLine(colors))"#)
        }
        return "    {\n" + fields.map { "      " + $0 }.joined(separator: ",\n") + "\n    }"
    }

    /// A skipped Color Rule or `colors` value as written, on one line like the rules around it: its
    /// pretty-printed lines joined without their indentation. Strings escape their
    /// own line feeds, so every `\n` is the layout's.
    private static func oneLine(_ value: JSONValue) -> String {
        value.prettyPrinted.split(separator: "\n").map { $0.drop { $0 == " " } }.joined(separator: " ")
    }

    private static func colorValue(_ color: PatternColor) -> String {
        color.isSingle ? quote(color.light) : #"{ "light": \#(quote(color.light)), "dark": \#(quote(color.dark)) }"#
    }

    /// A JSON string literal, escaped as the pretty-printer escapes, so `/` stays as
    /// is and URL regexes stay readable. The file is laid out by hand rather than
    /// pretty-printed so each `actions` list stays on one line.
    private static func quote(_ string: String) -> String {
        JSONValue.string(string).prettyPrinted
    }

    // MARK: Reading

    public static func load(_ data: Data) -> ConfigLoad {
        guard let text = String(data: data, encoding: .utf8) else { return fatal("Config file isn't UTF-8 text") }
        let root: JSONValue
        switch JSONValue.parseDocument(text) {
        case .success(let value): root = value
        case .failure(let error): return fatal("Config file isn't valid JSON (line \(error.line))")
        }
        guard case .object(let object) = root else { return fatal("Config file must be a JSON object") }
        guard case .array(let entries)? = field("patterns", in: object) else {
            return fatal(#"Config file needs a "patterns" array"#)
        }

        var warnings: [ConfigWarning] = []
        // Patterns are checked against every definition the file has, so one that
        // uses a broken definition is skipped rather than quietly falling back to
        // a bundled one of the same name.
        var skipped = SkippedEntries()
        let positioned = field("grok", in: object).map {
            grokDefinitions(from: $0, warnings: &warnings, skipped: &skipped.grok)
        } ?? []
        let written = positioned.map(\.definition)
        var grok: [GrokDefinition] = []
        for (position, definition) in positioned {
            if case .failure(let error) = compileGrokDefinition(definition, grok: written) {
                warnings.append(ConfigWarning("Grok Definition \(definition.name): \(error.message); skipped"))
                skipped.grok.append(.init(position: position, entry: JSONEntry(key: definition.name, value: .string(definition.regex))))
            } else {
                grok.append(definition)
            }
        }
        skipped.grok.sort { $0.position < $1.position }
        var patterns: [Pattern] = []
        for (index, entry) in entries.enumerated() {
            switch pattern(from: entry, number: index + 1, grok: written, warnings: &warnings) {
            case .success(let pattern): patterns.append(pattern)
            case .failure(let problem):
                warnings.append(ConfigWarning(problem.message))
                skipped.patterns.append(.init(position: index, entry: entry))
            }
        }
        updateFormerPresetRegexes(in: &patterns)

        var config = Config(patterns: patterns, grok: grok)
        if let value = field("shortcut", in: object) {
            if case .string(let string) = value, let shortcut = Shortcut(string) {
                config.shortcut = shortcut
            } else {
                warnings.append(ConfigWarning(
                    #"Shortcut \#(describe(value)) isn't like "ctrl+option+t"; using \#(Shortcut.default)"#
                ))
            }
        }
        if let value = field("editorCommand", in: object) {
            if case .string(let string) = value {
                config.editorCommand = string.isEmpty ? nil : string
            } else {
                warnings.append(ConfigWarning(#""editorCommand" must be a string; ignored"#))
            }
        }
        // A double-click on a JSON Match copied it, raw or beautified; clicks are a
        // text view's now, and the card's Copy and Copy Beautified do it.
        if field("copyJSON", in: object) != nil {
            warnings.append(ConfigWarning(
                #""copyJSON" is ignored: ⌘-click a Match, then Copy or Copy Beautified"#
            ))
        }
        if let value = field("inspectorLayout", in: object) {
            if case .string(let string) = value, let layout = InspectorLayout(rawValue: string) {
                config.inspectorLayout = layout
            } else {
                warnings.append(ConfigWarning(
                    #""inspectorLayout" \#(describe(value)) isn't "tabs" or "list"; using "tabs""#
                ))
            }
        }
        if let value = field("appearance", in: object) {
            if case .string(let string) = value, let appearance = AppearanceSetting(rawValue: string) {
                config.appearance = appearance
            } else {
                warnings.append(ConfigWarning(
                    #""appearance" \#(describe(value)) isn't "system", "light" or "dark"; following the system"#
                ))
            }
        }
        if let value = field("clearSelectionAfter", in: object) {
            if case .number(let number) = value, let seconds = Int(number), seconds >= 0 {
                config.clearSelectionAfter = seconds
            } else {
                warnings.append(ConfigWarning(
                    #""clearSelectionAfter" \#(describe(value)) isn't a whole number of seconds; keeping the selection"#
                ))
            }
        }
        if let value = field("shortcuts", in: object) {
            if case .object(let entries) = value {
                config.shortcuts = commandShortcuts(from: entries, global: config.shortcut, warnings: &warnings)
            } else {
                warnings.append(ConfigWarning(#""shortcuts" \#(describe(value)) isn't an object; using the defaults"#))
            }
        }
        // Custom theme files were read here once; they're not supported for now.
        if field("theme", in: object) != nil {
            warnings.append(ConfigWarning(
                #""theme" is ignored: the JSON Viewer uses GitHub Light and Dark; "appearance" picks light or dark"#
            ))
        }
        return ConfigLoad(config: config, warnings: warnings, skipped: skipped)
    }

    /// The `grok` object's definitions, each with its position among the object's
    /// entries; a repeated name keeps its first place and its last regex. Entries
    /// that aren't a valid name and a string are skipped with a warning.
    private static func grokDefinitions(
        from value: JSONValue, warnings: inout [ConfigWarning], skipped: inout [SkippedEntries.Skipped<JSONEntry>]
    ) -> [(position: Int, definition: GrokDefinition)] {
        guard case .object(let entries) = value else {
            warnings.append(ConfigWarning(#""grok" \#(describe(value)) isn't like { "NAME": "regex" }; ignored"#))
            return []
        }
        var definitions: [(position: Int, definition: GrokDefinition)] = []
        for (position, entry) in entries.enumerated() {
            guard GrokDefinition.isValidName(entry.key) else {
                warnings.append(ConfigWarning(
                    #"Grok Definition "\#(entry.key)": a name is letters, digits and _ only; skipped"#
                ))
                skipped.append(.init(position: position, entry: entry))
                continue
            }
            guard case .string(let regex) = entry.value else {
                warnings.append(ConfigWarning("Grok Definition \(entry.key): its regex must be a string; skipped"))
                skipped.append(.init(position: position, entry: entry))
                continue
            }
            let definition = GrokDefinition(name: entry.key, regex: regex)
            if let index = definitions.firstIndex(where: { $0.definition.name == entry.key }) {
                definitions[index].definition = definition
            } else {
                definitions.append((position, definition))
            }
        }
        return definitions
    }

    /// Gives each Preset whose regex is one an earlier textier shipped for it
    /// (`Preset.formerRegexes`) the regex it ships now. The Preset is the first
    /// regex Pattern with its name, as Settings finds it; another sharing the name
    /// is a User Pattern and keeps its regex. Only the Config changes: the file
    /// keeps the old text until Settings next writes it.
    private static func updateFormerPresetRegexes(in patterns: inout [Pattern]) {
        for preset in Preset.all {
            guard let former = Preset.formerRegexes[preset.name],
                  let index = patterns.firstIndex(where: { $0.name == preset.name && $0.regex != nil }),
                  let regex = patterns[index].regex, former.contains(regex)
            else { continue }
            patterns[index].kind = preset.kind
        }
    }

    private static func fatal(_ message: String) -> ConfigLoad {
        ConfigLoad(config: nil, warnings: [ConfigWarning(message, isFatal: true)])
    }

    private struct Problem: Error {
        var message: String
    }

    /// The Pattern an entry describes, or why it's skipped. Problems that don't skip
    /// the Pattern (a bad color) go to `warnings`.
    private static func pattern(
        from entry: JSONValue, number: Int, grok: [GrokDefinition], warnings: inout [ConfigWarning]
    ) -> Result<Pattern, Problem> {
        guard case .object(let fields) = entry else {
            return .failure(Problem(message: "Pattern #\(number) isn't a JSON object; skipped"))
        }
        guard case .string(let name)? = field("name", in: fields), !name.isEmpty else {
            return .failure(Problem(message: #"Pattern #\#(number) has no "name"; skipped"#))
        }
        func skip(_ reason: String) -> Result<Pattern, Problem> {
            .failure(Problem(message: #"Pattern "\#(name)": \#(reason); skipped"#))
        }

        let kind: Pattern.Kind
        switch (field("regex", in: fields), field("builtin", in: fields)) {
        case (let regex?, nil):
            guard case .string(let source) = regex else { return skip(#""regex" must be a string"#) }
            if case .failure(let error) = compileRegex(source, grok: grok) { return skip(error.message) }
            kind = .regex(source)
        case (nil, let builtin?):
            guard case .string(let raw) = builtin, let id = BuiltinID(rawValue: raw) else {
                let known = BuiltinID.allCases.map { #""\#($0.rawValue)""# }.joined(separator: ", ")
                return skip("unknown builtin \(describe(builtin)) (known: \(known))")
            }
            kind = .builtin(id)
        case (nil, nil):
            return skip(#"needs "regex" or "builtin""#)
        case (_?, _?):
            return skip(#"has both "regex" and "builtin""#)
        }
        if let reserved = BuiltinID(rawValue: name), kind != .builtin(reserved) {
            return skip(#""\#(name)" is reserved for the Built-in Pattern"#)
        }

        guard case .array(let rawActions)? = field("actions", in: fields) else {
            return skip(#"needs an "actions" list"#)
        }
        var actions: [Action] = []
        for rawAction in rawActions {
            guard case .string(let raw) = rawAction, let action = Action(rawValue: raw) else {
                return skip("unknown action \(describe(rawAction))")
            }
            actions.append(action)
        }

        var enabled = true
        if let value = field("enabled", in: fields) {
            guard case .bool(let flag) = value else { return skip(#""enabled" must be true or false"#) }
            enabled = flag
        }

        var color: PatternColor?
        if let value = field("color", in: fields) {
            color = patternColor(from: value)
            if color == nil {
                warnings.append(ConfigWarning(
                    ##"Pattern "\##(name)": color \##(describe(value)) isn't like "#61afef", "#61afef80" or { "light": "#0969da", "dark": "#58a6ff" }; using the default"##
                ))
            }
        }

        var colorRules: [ColorRule]?
        var skippedColorRules: [SkippedEntries.Skipped<JSONValue>] = []
        if let value = field("colors", in: fields) {
            colorRules = self.colorRules(
                from: value, pattern: name, grok: grok, warnings: &warnings, skipped: &skippedColorRules
            )
        }

        var pattern = Pattern(
            name: name, kind: kind, enabled: enabled, actions: actions, color: color, colorRules: colorRules
        )
        pattern.skippedColorRules = skippedColorRules
        if colorRules == nil, let value = field("colors", in: fields) {
            // Not a list, so ignored; kept as written for the next write.
            pattern.skippedColors = value
        }
        return .success(pattern)
    }

    /// A `colors` list of `{ "when": regex, "color": color }`, each regex compiled
    /// among the file's Grok Definitions `grok`; a rule that can't be used is
    /// skipped with a warning and goes to `skipped` as written, the rest kept. Nil
    /// when `colors` isn't a list, as if it weren't there, so a shipped Pattern
    /// keeps its default rules.
    private static func colorRules(
        from value: JSONValue, pattern name: String, grok: [GrokDefinition], warnings: inout [ConfigWarning],
        skipped: inout [SkippedEntries.Skipped<JSONValue>]
    ) -> [ColorRule]? {
        guard case .array(let entries) = value else {
            warnings.append(ConfigWarning(#"Pattern "\#(name)": "colors" must be a list of color rules; ignored"#))
            return nil
        }
        var rules: [ColorRule] = []
        for (offset, entry) in entries.enumerated() {
            let number = offset + 1
            func skip(_ message: String) {
                warnings.append(ConfigWarning(message))
                skipped.append(.init(position: offset, entry: entry))
            }
            guard case .object(let fields) = entry, case .string(let when)? = field("when", in: fields),
                  let rawColor = field("color", in: fields)
            else {
                skip(#"Pattern "\#(name)": color rule #\#(number) isn't { "when": "…", "color": "…" }; skipped"#)
                continue
            }
            if case .failure(let error) = compileRegex(when, grok: grok, options: .caseInsensitive) {
                skip(#"Pattern "\#(name)": color rule #\#(number)'s "when": \#(error.message); skipped"#)
                continue
            }
            guard let color = patternColor(from: rawColor) else {
                skip(##"Pattern "\##(name)": color rule #\##(number)'s color \##(describe(rawColor)) isn't like "#61afef" or { "light": …, "dark": … }; skipped"##)
                continue
            }
            rules.append(ColorRule(when: when, color: color))
        }
        return rules
    }

    /// A `color` value: one hex string, or an object with a hex `light` and `dark`.
    private static func patternColor(from value: JSONValue) -> PatternColor? {
        switch value {
        case .string(let hex) where isHexColor(hex):
            return PatternColor(hex)
        case .object(let fields):
            guard case .string(let light)? = field("light", in: fields), isHexColor(light),
                  case .string(let dark)? = field("dark", in: fields), isHexColor(dark)
            else { return nil }
            return PatternColor(light: light, dark: dark)
        default:
            return nil
        }
    }

    /// `#RRGGBB` or `#RRGGBBAA`, any case.
    private static func isHexColor(_ string: String) -> Bool {
        let digits = string.unicodeScalars.dropFirst()
        return string.hasPrefix("#") && [6, 8].contains(digits.count)
            && digits.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0) }
    }

    /// The `shortcuts` object as the file writes it, every command in order.
    private static func shortcutsObject(_ shortcuts: CommandShortcuts) -> String {
        let commands = ShortcutCommand.allCases.map { "\(quote($0.rawValue)): \(quote(shortcuts[$0]?.description ?? ""))" }
        let modifiers = [
            "\(quote("selectTab")): \(quote(Shortcut.description(of: shortcuts.selectTab)))",
            "\(quote("matchClick")): \(quote(Shortcut.description(of: shortcuts.matchClick)))",
        ]
        return "{\n" + (commands + modifiers).map { "    " + $0 }.joined(separator: ",\n") + "\n  }"
    }

    /// The app's shortcuts from the `shortcuts` object: each written one in place
    /// of its default, `""` for none; what can't be used is warned about.
    private static func commandShortcuts(
        from entries: [JSONEntry], global: Shortcut, warnings: inout [ConfigWarning]
    ) -> CommandShortcuts {
        var shortcuts = CommandShortcuts.default
        let commands = Set(ShortcutCommand.allCases.map(\.rawValue))
        for key in Set(entries.map(\.key)).subtracting(commands).subtracting(["selectTab", "matchClick"]).sorted() {
            warnings.append(ConfigWarning(#""shortcuts" has no command "\#(key)"; ignored"#))
        }
        // Read first, then checked in command order, so the earlier command keeps a shared shortcut.
        for command in ShortcutCommand.allCases {
            guard let value = field(command.rawValue, in: entries) else { continue }
            guard case .string(let string) = value else {
                warnings.append(ConfigWarning(#"Shortcut "\#(command.rawValue)" \#(describe(value)) isn't a string; using its default"#))
                continue
            }
            if string.isEmpty {
                shortcuts[command] = nil
            } else if let shortcut = Shortcut(string) {
                shortcuts[command] = shortcut
            } else {
                warnings.append(ConfigWarning(#"Shortcut "\#(command.rawValue)" \#(describe(value)) isn't like "cmd+g"; using its default"#))
            }
        }
        for (key, keyPath) in [("selectTab", \CommandShortcuts.selectTab), ("matchClick", \CommandShortcuts.matchClick)] {
            guard let value = field(key, in: entries) else { continue }
            if case .string(let string) = value, let modifiers = Shortcut.modifiers(string) {
                shortcuts[keyPath: keyPath] = modifiers
            } else {
                warnings.append(ConfigWarning(#"Shortcut "\#(key)" \#(describe(value)) isn't modifiers like "cmd"; using "cmd""#))
            }
        }
        var checked = CommandShortcuts(assigned: [:], selectTab: shortcuts.selectTab, matchClick: shortcuts.matchClick)
        for command in ShortcutCommand.allCases {
            guard let shortcut = shortcuts[command] else { continue }
            if let problem = checked.problem(with: shortcut, for: command, global: global) {
                warnings.append(ConfigWarning(#"Shortcut "\#(command.rawValue)": \#(problem); left unassigned"#))
            } else {
                checked[command] = shortcut
            }
        }
        return checked
    }

    /// The value of `key` among an object's entries; a repeated key's last value wins.
    private static func field(_ key: String, in entries: [JSONEntry]) -> JSONValue? {
        entries.last { $0.key == key }?.value
    }

    /// A config value as the user wrote it, on one line, for warnings.
    private static func describe(_ value: JSONValue) -> String {
        value.prettyPrinted.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }
}
