import Foundation

/// How an Inspector tab lists its entries: by position in the Input, or sorted by
/// their values, one way or the other.
public enum EntryOrder: Sendable, Hashable, CaseIterable {
    case position
    case ascending
    case descending
}

/// What a tab's entries are sorted by.
public enum SortKind: Sendable, Equatable {
    /// A datetime's instant (offset-less ones read in the local time zone, as their
    /// Summary is): Earliest first, Latest first.
    case time
    /// A file path, then its line as a number.
    case path
    /// The text, numbers in it compared as numbers.
    case text

    /// What `order` is called in the sort menu.
    public func title(of order: EntryOrder) -> String {
        switch (self, order) {
        case (_, .position): "Position"
        case (.time, .ascending): "Earliest first"
        case (.time, .descending): "Latest first"
        case (_, .ascending): "A → Z"
        case (_, .descending): "Z → A"
        }
    }
}

extension InspectorTab {
    /// What the tab's entries sort by; nil for Plain Text, which keeps its order.
    public var sortKind: SortKind? {
        guard id != .plainText else { return nil }
        for entry in entries {
            switch entry.detail {
            case .datetime: return .time
            case .filePath: return .path
            case .text: continue
            default: return .text
            }
        }
        return .text
    }

    /// The entries' indices in the order `order` lists them. Ties keep their order
    /// in the Input; an entry without a value to sort by (a datetime that didn't
    /// parse) comes after the sorted ones, in Input order too.
    public func indices(in order: EntryOrder) -> [Int] {
        guard order != .position, let kind = sortKind else { return Array(entries.indices) }
        let keys = entries.map { SortKey($0, kind: kind) }
        let ascending = order == .ascending
        return entries.indices.sorted { a, b in
            switch (keys[a], keys[b]) {
            case (nil, nil): return a < b
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?):
                let comparison = x.compare(y)
                if comparison == .orderedSame { return a < b }
                return (comparison == .orderedAscending) == ascending
            }
        }
    }
}

/// An entry's value as its tab sorts it.
private enum SortKey {
    case time(Date)
    case path(NaturalText, line: Int)
    case text(NaturalText)

    init?(_ entry: InspectorEntry, kind: SortKind) {
        switch (kind, entry.detail) {
        case (.time, .datetime(let datetime)): self = .time(datetime.conversions.instant)
        case (.time, _): return nil
        case (.path, .filePath(let file)): self = .path(NaturalText(file.path), line: file.line ?? 0)
        case (.path, _): self = .path(NaturalText(entry.text), line: 0)
        case (.text, _): self = .text(NaturalText(entry.text))
        }
    }

    func compare(_ other: SortKey) -> ComparisonResult {
        switch (self, other) {
        case let (.time(a), .time(b)):
            return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        case let (.path(a, lineA), .path(b, lineB)):
            let byPath = a.compare(b)
            guard byPath == .orderedSame else { return byPath }
            return lineA == lineB ? .orderedSame : lineA < lineB ? .orderedAscending : .orderedDescending
        case let (.text(a), .text(b)):
            return a.compare(b)
        default:
            return .orderedSame
        }
    }
}

/// Text compared as people read it: letters without regard to case, and runs of
/// digits as the numbers they are (`ORD-9` before `ORD-10`). Its key is worked
/// out once per entry: lowercased, each run of digits without its leading zeros
/// and led by its length, so plain string comparison orders numbers by value.
struct NaturalText {
    private let key: String

    init(_ text: String) {
        var key = ""
        var digits = ""
        func flushDigits() {
            guard !digits.isEmpty else { return }
            let value = digits.drop { $0 == "0" }
            let number = value.isEmpty ? "0" : String(value)
            // Its length in two digits first: no number in a log has a hundred digits.
            key += (number.count < 10 ? "0" : "") + String(min(number.count, 99)) + number
            digits = ""
        }
        for character in text.lowercased() {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else {
                flushDigits()
                key.append(character)
            }
        }
        flushDigits()
        self.key = key
    }

    func compare(_ other: NaturalText) -> ComparisonResult {
        key == other.key ? .orderedSame : key < other.key ? .orderedAscending : .orderedDescending
    }
}
