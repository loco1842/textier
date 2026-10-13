import Foundation

/// Where Go to Line goes: a line, and a column on it when given, both from 1.
public struct LineTarget: Sendable, Equatable {
    public var line: Int
    public var column: Int?

    public init(line: Int, column: Int? = nil) {
        self.line = line
        self.column = column
    }

    /// Reads `120` or `120:15` (spaces around are fine); nil for anything else,
    /// line or column 0 included.
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              let line = Int(parts[0].trimmingCharacters(in: .whitespaces)), line >= 1 else { return nil }
        var column: Int?
        if parts.count == 2 {
            guard let value = Int(parts[1].trimmingCharacters(in: .whitespaces)), value >= 1 else { return nil }
            column = value
        }
        self.init(line: line, column: column)
    }

    /// The UTF-16 offset it lands on in a text whose lines start at `lineStarts`
    /// (offsets, the first 0) and which is `length` long: past the last line, on the
    /// last line; past a line's end, at its end.
    public func location(lineStarts: [Int], length: Int) -> Int {
        let index = min(line, lineStarts.count) - 1
        let start = lineStarts[index]
        // The line ends before its line break, or at the text's end.
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : length
        return min(start + (column ?? 1) - 1, max(start, end))
    }
}
