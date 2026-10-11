/// A named regex fragment that a Pattern's regex references as `%{NAME}`. It is
/// not a Pattern: it never matches on its own.
public struct GrokDefinition: Sendable, Equatable, Hashable {
    public var name: String
    /// The regex body, which can reference other definitions.
    public var regex: String

    public init(name: String, regex: String) {
        self.name = name
        self.regex = regex
    }

    /// Whether `name` can name a definition: letters, digits and `_`, as grok
    /// references spell it.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || $0 == "_") }
    }
}
