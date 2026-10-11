/// A Pattern's highlight color: one `#RRGGBB` or `#RRGGBBAA` value for the light
/// appearance and one for the dark. A single hex value fills both.
public struct PatternColor: Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    /// The same value in both appearances.
    public init(_ hex: String) {
        self.init(light: hex, dark: hex)
    }

    public init(stringLiteral hex: String) {
        self.init(hex)
    }

    /// Whether light and dark are the same value, so the config file can write it as one.
    public var isSingle: Bool { light == dark }
}

/// The colors Patterns get when the config doesn't give one: Radix step-9 hues,
/// one value for both appearances; `PatternColor.roles(in:)` derives the rest.
public enum Palette {
    /// Each Preset's and Built-in's color, by Pattern name. Orange is Radix's step
    /// 10, so white text on it reads at 3:1.
    public static let byName: [String: PatternColor] = [
        "json": "#ffc53d",
        "escaped-json": "#ef5f00",
        "url": "#0090ff",
        "datetime": "#6e56cf",
        "file path": "#46a758",
        "log level": "#e5484d",
    ]

    /// The colors User Patterns without one take, in order, skipping any another
    /// Pattern already uses: pink, cyan, lime, purple, grey.
    public static let forUserPatterns: [PatternColor] = ["#d6409f", "#00a2c7", "#bdee63", "#8e4ec6", "#8d8d8d"]

    /// The color of a Pattern that isn't in the Config being asked.
    public static let fallback: PatternColor = "#0090ff"

    /// Plain Text's neutral grey, which is not a Pattern's.
    public static let plainText: PatternColor = "#8b8d98"

    /// A good or bad state in a parsed view (a file that exists or not): green and red.
    public static let success: PatternColor = "#46a758"
    public static let failure: PatternColor = "#e5484d"
}

extension Config {
    /// The color `pattern`'s Matches are tinted in: its name's color in this
    /// Config, or else its own `color` or palette default.
    public func color(of pattern: Pattern) -> PatternColor {
        guard let index = patterns.firstIndex(of: pattern) else {
            return pattern.color ?? Palette.byName[pattern.name] ?? Palette.fallback
        }
        return resolvedColors[index]
    }

    /// The color of the group named `name`: its first Pattern's, or for a name no
    /// Pattern here has, its palette color by name.
    public func color(ofName name: String) -> PatternColor {
        patterns.first { $0.name == name }.map(color(of:)) ?? Palette.byName[name] ?? Palette.fallback
    }

    /// Every Pattern's color, in Config order. Patterns that share a name share
    /// one color, the first such Pattern's: its explicit `color`, or for a Preset
    /// or Built-in its palette color by name. Each remaining name takes the next
    /// palette color no other name uses, and once they are all used, cycles
    /// through `Palette.forUserPatterns`.
    public var resolvedColors: [PatternColor] {
        var names: [String] = []
        var colors: [String: PatternColor] = [:]
        for pattern in patterns where !names.contains(pattern.name) {
            names.append(pattern.name)
            colors[pattern.name] = pattern.color ?? Palette.byName[pattern.name]
        }
        var used = Set(colors.values)
        let candidates = Palette.forUserPatterns + Palette.byName.values.sorted { $0.light < $1.light }
        var cycled = 0
        for name in names where colors[name] == nil {
            if let unused = candidates.first(where: { !used.contains($0) }) {
                colors[name] = unused
                used.insert(unused)
            } else {
                colors[name] = Palette.forUserPatterns[cycled % Palette.forUserPatterns.count]
                cycled += 1
            }
        }
        return patterns.map { colors[$0.name]! }
    }
}
