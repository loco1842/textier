import Foundation

/// A rule that detects one kind of structured piece in the Input.
public struct Pattern: Sendable, Equatable {
    /// How a Pattern finds its Matches: a regex (Presets and User Patterns) or
    /// code (Built-in Patterns).
    public enum Kind: Sendable, Equatable {
        /// Regex source, run over the whole Input and anchored to nothing.
        case regex(String)
        case builtin(BuiltinID)
    }

    public var name: String
    public var kind: Kind
    public var enabled: Bool
    /// Ordered; the first is the default Action run on double-click.
    public var actions: [Action]
    /// Optional highlight color, as written in the config; `Config.color(of:)`
    /// resolves it against the palette.
    public var color: PatternColor?
    /// Colors by a Match's text, as written in the config (`colors`); nil when it
    /// has none, so a shipped Pattern's defaults apply (`effectiveColorRules`).
    public var colorRules: [ColorRule]?
    /// The `colors` entries the config file has but couldn't load, as written, each
    /// at its place in the list. Color Rules are only written by hand, so writing
    /// the file back (from Settings) keeps one the user is still fixing.
    public var skippedColorRules: [SkippedEntries.Skipped<JSONValue>] = []
    /// The config file's `colors` as written when it isn't a list, so it's ignored
    /// (`colorRules` is nil); writing the file back keeps it for the user to fix.
    public var skippedColors: JSONValue?

    public init(
        name: String, kind: Kind, enabled: Bool = true, actions: [Action], color: PatternColor? = nil,
        colorRules: [ColorRule]? = nil
    ) {
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.actions = actions
        self.color = color
        self.colorRules = colorRules
    }

    /// A regex Pattern: a Preset or a User Pattern.
    public init(
        name: String, regex: String, enabled: Bool = true, actions: [Action], color: PatternColor? = nil,
        colorRules: [ColorRule]? = nil
    ) {
        self.init(name: name, kind: .regex(regex), enabled: enabled, actions: actions, color: color, colorRules: colorRules)
    }

    /// The Color Rules that apply: the config's, or, when it gives none, those of the
    /// shipped Pattern of this name (none for a User Pattern).
    public var effectiveColorRules: [ColorRule] {
        colorRules ?? Pattern.shipped.first { $0.name == name }?.colorRules ?? []
    }

    /// The Patterns textier ships, in the default Config's order.
    public static let shipped = [Builtin.json, Builtin.escapedJSON] + Preset.all

    /// The regex source of a Preset or User Pattern; nil for a Built-in Pattern.
    public var regex: String? {
        if case .regex(let source) = kind { source } else { nil }
    }
}

/// A Color Rule: Matches whose text contains `when` (a regex, ignoring case) take
/// `color` instead of their Pattern's. A Pattern's rules are tried in order. Any
/// Pattern can have them: log levels by severity, HTTP statuses by class, an
/// environment name by its stage. `when` is read as a Pattern's regex is
/// (`compileRegex`), grok references and all.
public struct ColorRule: Sendable, Equatable {
    public var when: String
    public var color: PatternColor

    public init(when: String, color: PatternColor) {
        self.when = when
        self.color = color
    }

    /// `when`, compiled among the Grok Definitions `grok` to match ignoring case;
    /// nil when it can't be.
    func regex(grok: [GrokDefinition]) -> NSRegularExpression? {
        guard case .success(let compiled) = compileRegex(when, grok: grok, options: .caseInsensitive) else { return nil }
        return compiled.regex
    }
}

/// Which Built-in Pattern a Pattern is: the code that detects it, since a regex
/// can't express it. The config file names it by the raw value.
public enum BuiltinID: String, Sendable, Equatable, CaseIterable {
    case json
    case escapedJSON = "escaped-json"
}

/// The Built-in Patterns as they ship, each with its palette color written out so
/// the first-launch config file documents it.
public enum Builtin {
    /// JSON objects and arrays anywhere in the Input.
    public static let json = Pattern(
        name: "json", kind: .builtin(.json), actions: [.open, .copyPretty, .copy], color: Palette.byName["json"]
    )
    /// JSON objects and arrays escaped inside JSON string values, in the JSON Viewer.
    /// It never matches the Input itself.
    public static let escapedJSON = Pattern(
        name: "escaped-json", kind: .builtin(.escapedJSON), actions: [.open], color: Palette.byName["escaped-json"]
    )
}

/// Regex Patterns that ship with textier, each with its palette color written out.
public enum Preset {
    /// Every Preset, in the order the default Config lists them.
    public static let all = [url, datetime, filePath, logLevel]

    /// The regexes earlier versions of textier shipped for a Preset, by its name.
    /// A config file written then still has one; loading it gives the Preset its
    /// current regex instead, while a regex the user edited stays as written.
    public static let formerRegexes: [String: [String]] = [
        "url": [#"\bhttps?://[^\s"'`)\]}>]+"#],
        "log level": [#"\b(?:EMERGENCY|ALERT|CRITICAL|ERROR|WARNING|NOTICE|INFO|DEBUG)\b"#],
    ]

    /// `http`/`https` URLs, terminated by whitespace or a closing quote/bracket, and
    /// never on a trailing `.`, `,`, `;`, `:`, `!` or `?`, which end the sentence
    /// around it rather than the URL.
    public static let url = Pattern(
        name: "url",
        regex: #"\bhttps?://[^\s"'`)\]}>]*[^\s"'`)\]}>.,;:!?]"#,
        actions: [.openURL, .copy],
        color: Palette.byName["url"]
    )

    /// `YYYY-MM-DD` with an optional `T`/space time (minutes, seconds, fractional
    /// seconds, `Z` or offset), or a 10/13-digit Unix epoch as a whole word.
    public static let datetime = Pattern(
        name: "datetime",
        regex: #"\b\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(?:[T ](?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d+)?)?(?:Z|[+-](?:[01]\d|2[0-3]):?[0-5]\d)?)?(?![\w-])|\b\d{10}(?:\d{3})?\b"#,
        actions: [.copy],
        color: Palette.byName["datetime"]
    )

    /// Absolute (`/…`) or home-relative (`~/…`) paths with an optional `:line[:col]`.
    /// A path can't start mid-word or right after `:` or `/`, so the path part of a
    /// URL isn't one; it ends at whitespace, a quote, a bracket, `,`, `;`, `:` or `\`,
    /// and never on a trailing `.`.
    public static let filePath = Pattern(
        name: "file path",
        regex: #"(?<![\w.~/:\\-])(?:~/|/)(?!/)[^\s"'`:,;()\[\]{}<>\\]*[^\s"'`:,;()\[\]{}<>\\.](?::\d+(?::\d+)?)?"#,
        actions: [.openFile, .copy],
        color: Palette.byName["file path"]
    )

    /// The PSR-3 levels as whole words, in any case: Monolog writes them uppercase,
    /// other loggers lowercase or capitalized. Shipped disabled.
    public static let logLevel = Pattern(
        name: "log level",
        regex: #"(?i)\b(?:EMERGENCY|ALERT|CRITICAL|ERROR|WARNING|NOTICE|INFO|DEBUG)\b"#,
        enabled: false,
        actions: [.copy],
        color: Palette.byName["log level"],
        colorRules: [
            ColorRule(when: "EMERG|ALERT|CRIT|ERR", color: "#e5484d"),
            // Radix yellow, apart from json's amber.
            ColorRule(when: "WARN", color: "#ffe629"),
            ColorRule(when: "NOTICE|INFO", color: "#0090ff"),
            ColorRule(when: "DEBUG", color: "#8d8d8d"),
        ]
    )
}
