import Foundation

/// One colored stretch of JSON text.
public struct ColoredRange: Sendable, Equatable {
    /// UTF-16 range in the text passed to `colorize`.
    public var range: NSRange
    public var kind: JSONTokenKind
    public var style: TokenStyle

    public init(range: NSRange, kind: JSONTokenKind, style: TokenStyle) {
        self.range = range
        self.kind = kind
        self.style = style
    }
}

/// The JSON tokens of `text`, in order, each with `theme`'s style for its kind:
/// UTF-16 ranges that don't overlap, with whitespace between tokens left uncolored.
/// A string is one token, quotes and escapes included, so escaped JSON inside it
/// colors as the string. Text that stops being JSON is colored up to where it
/// stops (the Inspector only colors beautified JSON, so that's a safeguard).
public func colorize(_ text: String, theme: Theme) -> [ColoredRange] {
    jsonTokens(in: text).map { ColoredRange(range: $0.range, kind: $0.kind, style: theme.style(for: $0.kind)) }
}
