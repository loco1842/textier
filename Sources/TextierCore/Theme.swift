import Foundation

/// The kinds of JSON token syntax coloring tells apart.
public enum JSONTokenKind: Sendable, Equatable, Hashable, CaseIterable {
    case key
    case string
    case number
    case boolean
    case null
    /// Braces, brackets, `:` and `,`.
    case punctuation
}

/// How a token is drawn: a `#RRGGBB` or `#RRGGBBAA` color and a font style.
public struct TokenStyle: Sendable, Equatable {
    public var color: String
    public var fontStyle: FontStyle

    public init(color: String, fontStyle: FontStyle = []) {
        self.color = color
        self.fontStyle = fontStyle
    }
}

public struct FontStyle: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = FontStyle(rawValue: 1 << 0)
    public static let italic = FontStyle(rawValue: 1 << 1)
    public static let underline = FontStyle(rawValue: 1 << 2)
}

/// A VS Code color theme, reduced to what JSON coloring needs: the editor's
/// foreground and background, and a style per JSON token kind (ADR-0003).
public struct Theme: Sendable, Equatable {
    /// The file's `name`; empty when it has none.
    public var name: String
    /// `editor.foreground`; also the color of anything no scope rule covers.
    public var foreground: String
    /// `editor.background`.
    public var background: String
    public var styles: [JSONTokenKind: TokenStyle]

    public init(name: String, foreground: String, background: String, styles: [JSONTokenKind: TokenStyle]) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.styles = styles
    }

    /// The style for `kind`; the editor foreground when the theme has no rule for it.
    public func style(for kind: JSONTokenKind) -> TokenStyle {
        styles[kind] ?? TokenStyle(color: foreground)
    }

    /// Reads a VS Code theme JSON file: `name`, `type`, `colors` (`editor.foreground`
    /// and `editor.background`) and `tokenColors`. Comments and trailing commas are
    /// allowed, as VS Code allows them. A file that isn't a JSON object, or has
    /// neither `colors` nor a `tokenColors` list, is rejected; a rule with a bad
    /// color only loses that color.
    public static func load(_ data: Data) throws(ThemeError) -> Theme {
        guard let text = String(data: data, encoding: .utf8) else { throw ThemeError("Theme file isn't UTF-8 text") }
        let root: JSONValue
        switch JSONValue.parseDocument(try withoutCommentsAndTrailingCommas(text)) {
        case .success(let value): root = value
        case .failure(let error): throw ThemeError("Theme file isn't valid JSON (line \(error.line))")
        }
        guard case .object = root else { throw ThemeError("Theme file must be a JSON object") }

        let rules: [ScopeRule]
        switch root["tokenColors"] {
        case .array(let entries)?: rules = entries.compactMap(ScopeRule.init)
        case nil where root["colors"] != nil: rules = []
        case nil: throw ThemeError(#"Theme file has neither "tokenColors" nor "colors""#)
        case _?: throw ThemeError(#""tokenColors" must be a list of rules"#)
        }

        let isDark = root["type"] == .string("dark") || root["type"] == .string("hc")
        func editorColor(_ key: String) -> String? {
            guard case .string(let hex)? = root["colors"]?[key] else { return nil }
            return normalizedHex(hex)
        }
        let foreground = editorColor("editor.foreground") ?? (isDark ? "#d4d4d4" : "#000000")
        let background = editorColor("editor.background") ?? (isDark ? "#1e1e1e" : "#ffffff")

        var styles: [JSONTokenKind: TokenStyle] = [:]
        for kind in JSONTokenKind.allCases {
            styles[kind] = resolve(kind.scopes, rules: rules, base: TokenStyle(color: foreground))
        }
        let name = if case .string(let name)? = root["name"] { name } else { "" }
        return Theme(name: name, foreground: foreground, background: background, styles: styles)
    }

    /// GitHub Light Default, bundled.
    public static let githubLight = try! load(Data(BundledThemes.githubLight.utf8))
    /// GitHub Dark Default, bundled.
    public static let githubDark = try! load(Data(BundledThemes.githubDark.utf8))
}

extension JSONTokenKind {
    /// The scope stack VS Code's JSON grammar gives this token, outermost first. A
    /// string, number or literal is styled as it sits in an object value, and
    /// punctuation as an object's opening brace, since a Theme keeps one style per kind.
    var scopes: [String] {
        let value = ["source.json", "meta.structure.dictionary.json", "meta.structure.dictionary.value.json"]
        switch self {
        case .key: return ["source.json", "meta.structure.dictionary.json", "string.json", "support.type.property-name.json"]
        case .string: return value + ["string.quoted.double.json"]
        case .number: return value + ["constant.numeric.json"]
        case .boolean, .null: return value + ["constant.language.json"]
        case .punctuation: return ["source.json", "meta.structure.dictionary.json", "punctuation.definition.dictionary.begin.json"]
        }
    }
}

/// One `tokenColors` entry: its selectors (none for the defaults rule) and the
/// settings it defines.
private struct ScopeRule {
    /// Each selector's parts, outermost first: `"meta.structure.dictionary.json string"`
    /// is `["meta.structure.dictionary.json", "string"]`.
    var selectors: [[String]]
    var foreground: String?
    var fontStyle: FontStyle?

    init?(_ entry: JSONValue) {
        guard case .object = entry, case .object? = entry["settings"] else { return nil }
        let scopes: [String] = switch entry["scope"] {
        case .string(let scope)?: [scope]
        case .array(let scopes)?: scopes.compactMap { if case .string(let scope) = $0 { scope } else { nil } }
        default: []
        }
        selectors = scopes
            .flatMap { $0.split(separator: ",") }
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
        if case .string(let hex)? = entry["settings"]?["foreground"] { foreground = normalizedHex(hex) }
        if case .string(let style)? = entry["settings"]?["fontStyle"] {
            var parsed: FontStyle = []
            for word in style.split(whereSeparator: \.isWhitespace) {
                switch word {
                case "bold": parsed.insert(.bold)
                case "italic": parsed.insert(.italic)
                case "underline": parsed.insert(.underline)
                default: break
                }
            }
            fontStyle = parsed
        }
    }

    var isDefaults: Bool { selectors.isEmpty }

    /// How specifically the rule matches the last scope of `stack`, or nil when it
    /// doesn't: the dot-separated depth its selector's last part matches, then how
    /// many ancestor parts it names.
    func specificity(matching stack: ArraySlice<String>) -> (depth: Int, parents: Int)? {
        selectors.compactMap { parts -> (depth: Int, parents: Int)? in
            guard let scope = stack.last, let leaf = parts.last, matches(leaf, scope) else { return nil }
            // Ancestor parts must appear in order among the outer scopes.
            var ancestors = stack.dropLast()[...]
            for part in parts.dropLast().reversed() {
                guard let found = ancestors.lastIndex(where: { matches(part, $0) }) else { return nil }
                ancestors = ancestors[..<found]
            }
            return (leaf.split(separator: ".").count, parts.count - 1)
        }.max { ($0.depth, $0.parents) < ($1.depth, $1.parents) }
    }
}

/// Whether `selector` names `scope` or one of its parents: `string` matches
/// `string.quoted.double.json` but not `strings`.
private func matches(_ selector: String, _ scope: String) -> Bool {
    scope == selector || scope.hasPrefix(selector + ".")
}

/// The style of the innermost scope of `stack`, built as VS Code's tokenizer does:
/// the defaults rule, then for each scope outermost first, the rules matching it
/// from least to most specific (later rules winning ties), each overriding only
/// the settings it defines.
private func resolve(_ stack: [String], rules: [ScopeRule], base: TokenStyle) -> TokenStyle {
    var style = base
    func apply(_ rule: ScopeRule) {
        if let foreground = rule.foreground { style.color = foreground }
        if let fontStyle = rule.fontStyle { style.fontStyle = fontStyle }
    }
    rules.filter(\.isDefaults).forEach(apply)
    for end in stack.indices {
        let scoped = stack[...end]
        let matching = rules.enumerated().compactMap { index, rule in
            rule.specificity(matching: scoped).map { (rank: ($0.depth, $0.parents, index), rule: rule) }
        }
        matching.sorted { $0.rank < $1.rank }.forEach { apply($0.rule) }
    }
    return style
}

/// `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` as lowercase `#RRGGBB` or `#RRGGBBAA`;
/// nil for anything else.
private func normalizedHex(_ hex: String) -> String? {
    let digits = hex.lowercased().unicodeScalars.dropFirst()
    guard hex.hasPrefix("#"), digits.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
        return nil
    }
    switch digits.count {
    case 6, 8: return "#" + String(String.UnicodeScalarView(digits))
    case 3, 4: return "#" + digits.map { String(repeating: String($0), count: 2) }.joined()
    default: return nil
    }
}

/// `text` with `//` and `/* */` comments and trailing commas (a `,` before `}` or
/// `]`) blanked out, leaving strings alone, so the strict parser reads VS Code's
/// JSON-with-comments. Blanking keeps line numbers for error messages.
private func withoutCommentsAndTrailingCommas(_ text: String) throws(ThemeError) -> String {
    var scalars = Array(text.unicodeScalars)
    var index = 0
    var lastComma: Int?
    while index < scalars.count {
        switch scalars[index] {
        case "\"":
            lastComma = nil
            index += 1
            while index < scalars.count, scalars[index] != "\"" {
                index += scalars[index] == "\\" ? 2 : 1
            }
        case "/" where index + 1 < scalars.count && scalars[index + 1] == "/":
            while index < scalars.count, scalars[index] != "\n" {
                scalars[index] = " "
                index += 1
            }
            continue
        case "/" where index + 1 < scalars.count && scalars[index + 1] == "*":
            let start = index
            index += 2
            while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") { index += 1 }
            guard index + 1 < scalars.count else { throw ThemeError("Theme file has an unterminated /* comment") }
            for blank in start...index + 1 where scalars[blank] != "\n" { scalars[blank] = " " }
            index += 1
        case ",":
            lastComma = index
        case "}", "]":
            if let comma = lastComma { scalars[comma] = " " }
            lastComma = nil
        case " ", "\t", "\n", "\r":
            break
        default:
            lastComma = nil
        }
        index += 1
    }
    var result = String.UnicodeScalarView()
    result.append(contentsOf: scalars)
    return String(result)
}

/// Why a theme file couldn't be used.
public struct ThemeError: Error, Sendable, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}
