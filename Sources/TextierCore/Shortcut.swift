import Foundation

/// The global keyboard shortcut, as the config file writes it: modifiers and one key
/// joined by `+`, such as `"ctrl+option+t"`.
///
/// Modifiers are `ctrl` (or `control`), `option` (or `opt`, `alt`), `shift` and `cmd`
/// (or `command`); at least one of `ctrl`, `option` or `cmd` is required, so the
/// shortcut can't swallow ordinary typing. The key is a letter, a digit, `f1`…`f12`
/// or `space`. Case and spaces around `+` don't matter.
public struct Shortcut: Sendable, Equatable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var modifiers: Modifiers
    /// Lowercase key name; one of `Shortcut.keys`.
    public var key: String

    /// ⌃⌥T.
    public static let `default` = Shortcut(modifiers: [.control, .option], key: "t")!

    /// Every key name a Shortcut accepts.
    public static let keys: Set<String> = Set(
        "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init) + (1...12).map { "f\($0)" } + ["space"]
    )

    /// Canonical names in macOS order (⌃⌥⇧⌘); `description` writes these.
    private static let modifierNames: [(Modifiers, String)] = [
        (.control, "ctrl"), (.option, "option"), (.shift, "shift"), (.command, "cmd"),
    ]

    private static let modifierAliases: [String: Modifiers] = [
        "ctrl": .control, "control": .control,
        "option": .option, "opt": .option, "alt": .option,
        "shift": .shift,
        "cmd": .command, "command": .command,
    ]

    public init?(modifiers: Modifiers, key: String) {
        guard Self.keys.contains(key), !modifiers.isDisjoint(with: [.control, .option, .command]) else {
            return nil
        }
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses a config string such as `"ctrl+option+t"`; nil if it isn't a Shortcut.
    public init?(_ string: String) {
        let parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last else { return nil }
        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            guard let modifier = Self.modifierAliases[name] else { return nil }
            modifiers.insert(modifier)
        }
        self.init(modifiers: modifiers, key: key)
    }

    public var description: String {
        (Self.modifierNames.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }
}
