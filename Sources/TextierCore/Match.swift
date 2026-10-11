import Foundation

/// One region of the Input that a Pattern detected.
public struct Match: Sendable, Equatable {
    /// UTF-16 range in the Input, as `NSString` and `NSTextView` count it.
    public var range: NSRange
    public var text: String
    public var patternName: String
    /// The Pattern that found it: its index in the Config `detect` ran with.
    /// Patterns can share a name, so this, not the name, says whose Actions apply.
    public var patternIndex: Int
    /// The Actions of the Pattern that found it.
    public var actions: [Action]
    /// The Pattern's resolved highlight color; `detect` always sets it.
    public var color: PatternColor?
    /// Matches found inside this one, ordered by position. The Panel highlights
    /// only top-level Matches; children surface in the Match Window.
    public var children: [Match]
    /// The named captures that took part in the Match, in regex order.
    public var fields: [Field]

    public init(
        range: NSRange, text: String, patternName: String, patternIndex: Int, actions: [Action],
        color: PatternColor? = nil, children: [Match] = [], fields: [Field] = []
    ) {
        self.range = range
        self.text = text
        self.patternName = patternName
        self.patternIndex = patternIndex
        self.actions = actions
        self.color = color
        self.children = children
        self.fields = fields
    }
}

/// A Field of one Match: a named capture in its Pattern's regex, and what it
/// captured.
public struct Field: Sendable, Equatable {
    /// The name as written in the regex.
    public var name: String
    /// `int` or `float`, from grok's `%{NAME:field:type}`.
    public var type: String?
    public var value: String
    /// UTF-16 range in the text that was detected in.
    public var range: NSRange

    public init(name: String, type: String? = nil, value: String, range: NSRange) {
        self.name = name
        self.type = type
        self.value = value
        self.range = range
    }

    /// What the Field's row is labelled: `ms (int)` when grok gave a type.
    public var label: String {
        type.map { "\(name) (\($0))" } ?? name
    }
}
