/// The small symbol that marks a Pattern name wherever the name appears, beside
/// its color: one per Built-in Pattern and Preset, one shared by every User
/// Pattern, and one for Plain Text. The app draws each as an SF Symbol.
public enum Glyph: String, Sendable, Equatable, CaseIterable {
    case json
    case escapedJSON = "escaped-json"
    case url
    case datetime
    case filePath = "file path"
    case logLevel = "log level"
    case userPattern
    case plainText
}

extension Config {
    /// The Glyph of the tab for Pattern name `name`, decided by the first Pattern
    /// with that name, as its color is: a Built-in Pattern's own, a Preset's own
    /// (the first regex Pattern with a Preset's name is that Preset), or else the
    /// User Pattern Glyph. A name no Pattern here has is read as a Built-in's or a
    /// Preset's name.
    public func glyph(ofName name: String) -> Glyph {
        switch patterns.first(where: { $0.name == name })?.kind {
        case .builtin(.json): .json
        case .builtin(.escapedJSON): .escapedJSON
        case .regex:
            Preset.all.contains { $0.name == name } ? Glyph(rawValue: name) ?? .userPattern : .userPattern
        case nil:
            Glyph(rawValue: name).flatMap { [.userPattern, .plainText].contains($0) ? nil : $0 } ?? .userPattern
        }
    }
}
