import Foundation

/// A JSONPath query (RFC 9535), as the JSON Viewer's search runs it: `$.backtrace[*].file`,
/// `$..line`, `$.backtrace[?@.line > 100 && search(@.file, 'vendor')]`.
///
/// Supported: name, wildcard, index, slice and filter selectors, child and
/// descendant segments, several selectors in one bracket; in filters, `==` `!=` `<`
/// `<=` `>` `>=`, `&&` `||` `!` and parentheses, `@` and `$` queries (alone, they test
/// that something is there), and the functions `length`, `count`, `value`, `match`
/// and `search` (regular expressions in NSRegularExpression's syntax, a superset of
/// RFC 9485's). Results come in document order, each with its path; an object with a
/// key twice gives its first for that name, and each of them for a wildcard.
public struct JSONPathQuery: Sendable {
    private let segments: [Segment]

    public init(_ text: String) throws(JSONPathError) {
        var parser = Parser(text)
        segments = try parser.query()
    }

    /// The nodes the query selects in `root`.
    public func evaluate(_ root: JSONValue) -> [JSONPathResult] {
        Self.apply(segments, to: [JSONPathResult(path: [], ordinals: [], value: root)], root: root)
    }

    // MARK: Evaluation

    private static func apply(_ segments: [Segment], to start: [JSONPathResult], root: JSONValue) -> [JSONPathResult] {
        segments.reduce(start) { nodes, segment in
            switch segment {
            case .child(let selectors):
                nodes.flatMap { node in selectors.flatMap { select($0, in: node, root: root) } }
            case .descendant(let selectors):
                nodes.flatMap { node in
                    descendantsAndSelf(of: node).flatMap { inner in selectors.flatMap { select($0, in: inner, root: root) } }
                }
            }
        }
    }

    private static func descendantsAndSelf(of node: JSONPathResult) -> [JSONPathResult] {
        [node] + children(of: node).flatMap(descendantsAndSelf)
    }

    private static func children(of node: JSONPathResult) -> [JSONPathResult] {
        switch node.value {
        case .object(let entries):
            entries.enumerated().map { node.child(.key($1.key), at: $0, value: $1.value) }
        case .array(let elements):
            elements.enumerated().map { node.child(.index($0), at: $0, value: $1) }
        default:
            []
        }
    }

    private static func select(_ selector: Selector, in node: JSONPathResult, root: JSONValue) -> [JSONPathResult] {
        switch selector {
        case .name(let name):
            guard case .object(let entries) = node.value, let ordinal = entries.firstIndex(where: { $0.key == name })
            else { return [] }
            return [node.child(.key(name), at: ordinal, value: entries[ordinal].value)]
        case .wildcard:
            return children(of: node)
        case .index(let index):
            guard case .array(let elements) = node.value else { return [] }
            let normalized = index < 0 ? elements.count + index : index
            guard elements.indices.contains(normalized) else { return [] }
            return [node.child(.index(normalized), at: normalized, value: elements[normalized])]
        case .slice(let start, let end, let step):
            guard case .array(let elements) = node.value else { return [] }
            return sliceIndices(count: elements.count, start: start, end: end, step: step ?? 1).map {
                node.child(.index($0), at: $0, value: elements[$0])
            }
        case .filter(let expression):
            return children(of: node).filter { holds(expression, current: $0.value, root: root) }
        }
    }

    /// RFC 9535's slice: bounds counted from the end when negative, clamped, walked
    /// by `step` in either direction; a zero step selects nothing.
    private static func sliceIndices(count: Int, start: Int?, end: Int?, step: Int) -> [Int] {
        guard step != 0 else { return [] }
        func normalized(_ index: Int) -> Int { index >= 0 ? index : count + index }
        if step > 0 {
            let lower = min(max(normalized(start ?? 0), 0), count)
            let upper = min(max(normalized(end ?? count), 0), count)
            return Array(stride(from: lower, to: upper, by: step))
        }
        let upper = min(max(normalized(start ?? count - 1), -1), count - 1)
        let lower = min(max(end.map(normalized) ?? -1, -1), count - 1)
        return Array(stride(from: upper, to: lower, by: step))
    }

    private static func holds(_ expression: Expression, current: JSONValue, root: JSONValue) -> Bool {
        switch expression {
        case .or(let terms): terms.contains { holds($0, current: current, root: root) }
        case .and(let terms): terms.allSatisfy { holds($0, current: current, root: root) }
        case .not(let inner): !holds(inner, current: current, root: root)
        case .test(.function(let call)):
            switch evaluate(call, current: current, root: root) {
            case .logical(let result): result
            case .value(let value): value != nil
            }
        case .test(let operand):
            !nodes(of: operand, current: current, root: root).isEmpty
        case .compare(let left, let comparison, let right):
            compare(
                value(of: left, current: current, root: root), comparison,
                value(of: right, current: current, root: root)
            )
        }
    }

    /// What an operand selects: a literal is itself, a query its nodes, a function
    /// its value (nothing when it has none).
    private static func nodes(of operand: Operand, current: JSONValue, root: JSONValue) -> [JSONValue] {
        switch operand {
        case .literal(let value):
            return [value]
        case .query(let fromRoot, let segments):
            let start = fromRoot ? root : current
            return apply(segments, to: [JSONPathResult(path: [], ordinals: [], value: start)], root: root).map(\.value)
        case .function(let call):
            if case .value(let value?) = evaluate(call, current: current, root: root) { return [value] }
            return []
        }
    }

    /// An operand's one value, or nothing when it selects none or several.
    private static func value(of operand: Operand, current: JSONValue, root: JSONValue) -> JSONValue? {
        let selected = nodes(of: operand, current: current, root: root)
        return selected.count == 1 ? selected[0] : nil
    }

    private enum FunctionResult {
        case value(JSONValue?)
        case logical(Bool)
    }

    private static func evaluate(_ call: FunctionCall, current: JSONValue, root: JSONValue) -> FunctionResult {
        func argument(_ index: Int) -> JSONValue? {
            call.arguments.indices.contains(index) ? value(of: call.arguments[index], current: current, root: root) : nil
        }
        switch call.name {
        case "length":
            switch argument(0) {
            case .string(let string)?: return .value(.number(String(string.unicodeScalars.count)))
            case .array(let elements)?: return .value(.number(String(elements.count)))
            case .object(let entries)?: return .value(.number(String(entries.count)))
            default: return .value(nil)
            }
        case "count":
            let count = call.arguments.first.map { nodes(of: $0, current: current, root: root).count } ?? 0
            return .value(.number(String(count)))
        case "value":
            return .value(argument(0))
        default:  // match, search
            guard case .string(let string)? = argument(0), case .string(let pattern)? = argument(1),
                  let regex = try? NSRegularExpression(pattern: call.name == "match" ? "\\A(?:\(pattern))\\z" : pattern)
            else { return .logical(false) }
            let range = NSRange(string.startIndex..., in: string)
            return .logical(regex.firstMatch(in: string, range: range) != nil)
        }
    }

    private static func compare(_ left: JSONValue?, _ comparison: Comparison, _ right: JSONValue?) -> Bool {
        switch comparison {
        case .equal: equal(left, right)
        case .notEqual: !equal(left, right)
        case .less: less(left, right)
        case .lessOrEqual: less(left, right) || equal(left, right)
        case .greater: less(right, left)
        case .greaterOrEqual: less(right, left) || equal(left, right)
        }
    }

    /// Nothing equals nothing; numbers compare by value; otherwise like with like.
    private static func equal(_ left: JSONValue?, _ right: JSONValue?) -> Bool {
        switch (left, right) {
        case (nil, nil): true
        case (.number(let a)?, .number(let b)?): order(a, b) == .orderedSame
        case (.array(let a)?, .array(let b)?): a.count == b.count && zip(a, b).allSatisfy { equal($0, $1) }
        case (.object(let a)?, .object(let b)?):
            a.count == b.count && a.allSatisfy { entry in b.contains { $0.key == entry.key && equal($0.value, entry.value) } }
        case (let a?, let b?): a == b
        default: false
        }
    }

    /// Only numbers with numbers and strings with strings are ordered.
    private static func less(_ left: JSONValue?, _ right: JSONValue?) -> Bool {
        switch (left, right) {
        case (.number(let a)?, .number(let b)?): order(a, b) == .orderedAscending
        case (.string(let a)?, .string(let b)?): Array(a.unicodeScalars.map(\.value)).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
        default: false
        }
    }

    /// How two JSON numbers order by value. As Decimals, which hold 38 digits, so
    /// 64-bit IDs that a Double rounds together stay apart and `1.0` equals `1`; as
    /// Doubles only past a Decimal's exponent range.
    private static func order(_ left: String, _ right: String) -> ComparisonResult {
        let posix = Locale(identifier: "en_US_POSIX")
        if let a = Decimal(string: left, locale: posix), let b = Decimal(string: right, locale: posix),
           !a.isNaN, !b.isNaN {
            return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
        }
        let a = Double(left) ?? 0
        let b = Double(right) ?? 0
        return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    }
}

/// One node a JSONPath query selects: where it is, and its value.
public struct JSONPathResult: Sendable, Equatable {
    public var path: [JSONPathComponent]
    /// Each step's place among its parent's entries or elements, a step of `path`
    /// each: what tells apart two entries of an object with the same key.
    public var ordinals: [Int]
    public var value: JSONValue

    public init(path: [JSONPathComponent], ordinals: [Int], value: JSONValue) {
        self.path = path
        self.ordinals = ordinals
        self.value = value
    }

    /// The child reached by `component`, the parent's `ordinal`th entry or element.
    fileprivate func child(_ component: JSONPathComponent, at ordinal: Int, value: JSONValue) -> JSONPathResult {
        JSONPathResult(path: path + [component], ordinals: ordinals + [ordinal], value: value)
    }
}

/// Why a JSONPath query can't be read, with the 1-based position: "Expected , or ] at 14".
public struct JSONPathError: Error, Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

// MARK: Syntax

private enum Segment: Sendable {
    case child([Selector])
    case descendant([Selector])
}

private enum Selector: Sendable {
    case name(String)
    case wildcard
    case index(Int)
    case slice(Int?, Int?, Int?)
    case filter(Expression)
}

private indirect enum Expression: Sendable {
    case or([Expression])
    case and([Expression])
    case not(Expression)
    case compare(Operand, Comparison, Operand)
    case test(Operand)
}

private indirect enum Operand: Sendable {
    case literal(JSONValue)
    case query(fromRoot: Bool, [Segment])
    case function(FunctionCall)
}

private struct FunctionCall: Sendable {
    var name: String
    var arguments: [Operand]
}

private enum Comparison: Sendable {
    case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
}

/// A recursive-descent reader of the query text, by character.
private struct Parser {
    private let characters: [Character]
    private var position = 0

    static let functions: Set<String> = ["length", "count", "value", "match", "search"]

    init(_ text: String) {
        characters = Array(text)
    }

    private var current: Character? { position < characters.count ? characters[position] : nil }

    private func peek(_ offset: Int) -> Character? {
        position + offset < characters.count ? characters[position + offset] : nil
    }

    private func fail(_ message: String, at index: Int? = nil) -> JSONPathError {
        JSONPathError(message: "\(message) at \((index ?? position) + 1)")
    }

    private mutating func skipSpaces() {
        while let character = current, character == " " || character == "\t" || character == "\n" || character == "\r" {
            position += 1
        }
    }

    private mutating func consume(_ text: String) -> Bool {
        let expected = Array(text)
        guard position + expected.count <= characters.count,
              Array(characters[position..<position + expected.count]) == expected
        else { return false }
        position += expected.count
        return true
    }

    mutating func query() throws(JSONPathError) -> [Segment] {
        guard current == "$" else { throw fail("A query starts with $", at: 0) }
        position += 1
        let segments = try self.segments()
        skipSpaces()
        if let character = current { throw fail("Unexpected \(character)") }
        return segments
    }

    /// Segments until something that doesn't start one; spaces before a segment are allowed.
    private mutating func segments() throws(JSONPathError) -> [Segment] {
        var segments: [Segment] = []
        while true {
            let before = position
            skipSpaces()
            if consume("..") {
                if current == "[" {
                    segments.append(.descendant(try bracket()))
                } else {
                    segments.append(.descendant([try shorthand()]))
                }
            } else if consume(".") {
                segments.append(.child([try shorthand()]))
            } else if current == "[" {
                segments.append(.child(try bracket()))
            } else {
                position = before
                return segments
            }
        }
    }

    /// After a dot: a name or `*`.
    private mutating func shorthand() throws(JSONPathError) -> Selector {
        if consume("*") { return .wildcard }
        guard let first = current, first.isLetter || first == "_" || !first.isASCII else {
            throw fail("Expected a name or *")
        }
        var name = ""
        while let character = current, character.isLetter || character.isNumber || character == "_" || !character.isASCII {
            name.append(character)
            position += 1
        }
        return .name(name)
    }

    private mutating func bracket() throws(JSONPathError) -> [Selector] {
        position += 1  // [
        var selectors: [Selector] = []
        while true {
            selectors.append(try selector())
            skipSpaces()
            if consume(",") { continue }
            if consume("]") { return selectors }
            throw fail("Expected , or ]")
        }
    }

    private mutating func selector() throws(JSONPathError) -> Selector {
        skipSpaces()
        guard let character = current, character != "]" else { throw fail("Expected a selector") }
        switch character {
        case "'", "\"":
            return .name(try string())
        case "*":
            position += 1
            return .wildcard
        case "?":
            position += 1
            return .filter(try or())
        default:
            let start = try integer()
            skipSpaces()
            guard consume(":") else {
                guard let start else { throw fail("Expected a selector") }
                return .index(start)
            }
            skipSpaces()
            let end = try integer()
            skipSpaces()
            var step: Int?
            if consume(":") {
                skipSpaces()
                step = try integer()
            }
            return .slice(start, end, step)
        }
    }

    private mutating func integer() throws(JSONPathError) -> Int? {
        let start = position
        if current == "-" { position += 1 }
        while let character = current, character.isASCII, character.isNumber { position += 1 }
        let text = String(characters[start..<position])
        if text.isEmpty { return nil }
        guard let value = Int(text) else { throw fail("Expected a number", at: start) }
        return value
    }

    /// A single- or double-quoted string, with JSON's escapes (and `\'`). Any other
    /// escape is a mistake, as RFC 9535 has it, rather than dropped quietly: a regex's
    /// `\d` is written `\\d`.
    private mutating func string() throws(JSONPathError) -> String {
        let start = position
        let quote = characters[position]
        position += 1
        var result = ""
        while let character = current {
            position += 1
            if character == quote { return result }
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let escaped = current else { break }
            position += 1
            switch escaped {
            case "b": result.append("\u{8}")
            case "f": result.append("\u{C}")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "u":
                let hex = String(characters[position..<min(position + 4, characters.count)])
                guard hex.count == 4, let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw fail("Bad \\u escape", at: position - 2)
                }
                result.unicodeScalars.append(scalar)
                position += 4
            case "\\", "/", "'", "\"": result.append(escaped)
            default: throw fail("Bad escape \\\(escaped): write \\\\\(escaped) for a regex escape", at: position - 2)
            }
        }
        throw fail("Unclosed string", at: start)
    }

    // MARK: Filters

    private mutating func or() throws(JSONPathError) -> Expression {
        var terms = [try and()]
        while true {
            skipSpaces()
            guard consume("||") else { break }
            terms.append(try and())
        }
        return terms.count == 1 ? terms[0] : .or(terms)
    }

    private mutating func and() throws(JSONPathError) -> Expression {
        var terms = [try basic()]
        while true {
            skipSpaces()
            guard consume("&&") else { break }
            terms.append(try basic())
        }
        return terms.count == 1 ? terms[0] : .and(terms)
    }

    private mutating func basic() throws(JSONPathError) -> Expression {
        skipSpaces()
        if consume("!") {
            skipSpaces()
            return .not(try basic())
        }
        if consume("(") {
            let inner = try or()
            skipSpaces()
            guard consume(")") else { throw fail("Expected )") }
            return inner
        }
        let start = position
        let left = try operand()
        skipSpaces()
        if let comparison = self.comparison() {
            skipSpaces()
            return .compare(left, comparison, try operand())
        }
        if case .literal = left { throw fail("Expected a comparison", at: start) }
        return .test(left)
    }

    private mutating func comparison() -> Comparison? {
        for (text, comparison) in [("==", Comparison.equal), ("!=", .notEqual), ("<=", .lessOrEqual),
                                   (">=", .greaterOrEqual), ("<", .less), (">", .greater)] where consume(text) {
            return comparison
        }
        return nil
    }

    private mutating func operand() throws(JSONPathError) -> Operand {
        skipSpaces()
        guard let character = current else { throw fail("Expected a value to compare") }
        switch character {
        case "@", "$":
            position += 1
            return .query(fromRoot: character == "$", try segments())
        case "'", "\"":
            return .literal(.string(try string()))
        case "-", "0"..."9":
            return .literal(try number())
        default:
            if consume("true") { return .literal(.bool(true)) }
            if consume("false") { return .literal(.bool(false)) }
            if consume("null") { return .literal(.null) }
            guard character.isLetter else { throw fail("Expected a value to compare") }
            return .function(try function())
        }
    }

    private mutating func number() throws(JSONPathError) -> JSONValue {
        let start = position
        while let character = current, character.isNumber || "+-.eE".contains(character) { position += 1 }
        let text = String(characters[start..<position])
        guard case .number? = JSONValue.parse(text) else { throw fail("Expected a number", at: start) }
        return .number(text)
    }

    private mutating func function() throws(JSONPathError) -> FunctionCall {
        let start = position
        var name = ""
        while let character = current, character.isLetter || character.isNumber || character == "_" {
            name.append(character)
            position += 1
        }
        guard Self.functions.contains(name) else { throw fail("Unknown function \(name)", at: start) }
        skipSpaces()
        guard consume("(") else { throw fail("Expected (") }
        var arguments: [Operand] = []
        skipSpaces()
        if !consume(")") {
            while true {
                arguments.append(try operand())
                skipSpaces()
                if consume(",") { continue }
                guard consume(")") else { throw fail("Expected , or )") }
                break
            }
        }
        return FunctionCall(name: name, arguments: arguments)
    }
}
