import Foundation

/// A JSON value that keeps object keys in their source order (ADR-0002).
public indirect enum JSONValue: Sendable, Equatable {
    /// Entries in source order; duplicate keys are kept.
    case object([JSONEntry])
    case array([JSONValue])
    /// The unescaped string.
    case string(String)
    /// The number's source text, so pretty-printing never changes it (`1.50`, `1E+2`).
    case number(String)
    case bool(Bool)
    case null
}

/// One key/value pair of a JSON object.
public struct JSONEntry: Sendable, Equatable {
    public var key: String
    public var value: JSONValue

    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }
}

extension JSONValue {
    /// Parses `text` as one JSON document, allowing surrounding whitespace.
    /// Returns nil for anything that isn't strict RFC 8259 JSON.
    public static func parse(_ text: String) -> JSONValue? {
        try? parseDocument(text).get()
    }

    /// The line where `text` stops being one JSON document; nil when it is one.
    public static func errorLine(in text: String) -> Int? {
        if case .failure(let error) = parseDocument(text) { error.line } else { nil }
    }

    /// Parses `text` like `parse(_:)`, or reports the line where it stops being JSON.
    static func parseDocument(_ text: String) -> Result<JSONValue, JSONSyntaxError> {
        let units = Array(text.utf16)
        var parser = JSONParser(units)
        parser.skipWhitespace()
        if let value = parser.parseValue() {
            parser.skipWhitespace()
            if parser.isAtEnd { return .success(value) }
        }
        let failedAt = min(parser.position, units.count)
        return .failure(JSONSyntaxError(line: units[..<failedAt].count { $0 == 0x0A } + 1))
    }

    /// Parses one JSON value starting exactly at `offset` (in UTF-16 code units) and
    /// returns it with the number of UTF-16 code units it spans. Text after the value
    /// is ignored.
    public static func scan(_ text: String, at offset: Int) -> (value: JSONValue, length: Int)? {
        scan(Array(text.utf16), at: offset)
    }

    static func scan(_ units: [UInt16], at offset: Int) -> (value: JSONValue, length: Int)? {
        guard units.indices.contains(offset) else { return nil }
        var parser = JSONParser(units, at: offset)
        guard let value = parser.parseValue() else { return nil }
        return (value, parser.position - offset)
    }

    /// The value as JSON with 2-space indentation, keys in source order, string
    /// escapes normalised and no trailing whitespace or newline.
    public var prettyPrinted: String {
        var output = ""
        write(to: &output, indent: "")
        return output
    }

    private func write(to output: inout String, indent: String) {
        switch self {
        case .object(let entries):
            guard !entries.isEmpty else { output += "{}"; return }
            let inner = indent + "  "
            output += "{\n"
            for (index, entry) in entries.enumerated() {
                output += inner
                writeString(entry.key, to: &output)
                output += ": "
                entry.value.write(to: &output, indent: inner)
                output += index == entries.count - 1 ? "\n" : ",\n"
            }
            output += indent + "}"
        case .array(let elements):
            guard !elements.isEmpty else { output += "[]"; return }
            let inner = indent + "  "
            output += "[\n"
            for (index, element) in elements.enumerated() {
                output += inner
                element.write(to: &output, indent: inner)
                output += index == elements.count - 1 ? "\n" : ",\n"
            }
            output += indent + "]"
        case .string(let string):
            writeString(string, to: &output)
        case .number(let source):
            output += source
        case .bool(let bool):
            output += bool ? "true" : "false"
        case .null:
            output += "null"
        }
    }
}

/// Where a document stopped being JSON: the 1-based line of the parser's position
/// when it gave up.
struct JSONSyntaxError: Error, Equatable {
    var line: Int
}

/// Writes `string` as a JSON string literal: only `"`, `\` and control characters
/// are escaped; everything else, `/` and non-ASCII included, is written as is.
private func writeString(_ string: String, to output: inout String) {
    output += "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": output += "\\\""
        case "\\": output += "\\\\"
        case "\n": output += "\\n"
        case "\r": output += "\\r"
        case "\t": output += "\\t"
        case "\u{8}": output += "\\b"
        case "\u{C}": output += "\\f"
        case _ where scalar.value < 0x20:
            let hex = String(scalar.value, radix: 16)
            output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        default:
            output.unicodeScalars.append(scalar)
        }
    }
    output += "\""
}

/// One token of JSON text, for syntax coloring.
struct JSONToken: Equatable {
    /// UTF-16 range in the text.
    var range: NSRange
    var kind: JSONTokenKind
}

/// The tokens of the JSON value at the start of `text` (after whitespace), in order.
/// Where the text stops being JSON, the tokens stop: those before it are kept, and
/// the token it stops in and everything after are left out.
func jsonTokens(in text: String) -> [JSONToken] {
    var parser = JSONParser(Array(text.utf16), recordingTokens: true)
    parser.skipWhitespace()
    _ = parser.parseValue()
    return parser.tokens
}

/// The tokens of `units` when they're one JSON document, with only whitespace
/// around it; nil otherwise. One pass, where checking with `JSONValue.parse` and
/// then taking `jsonTokens` would parse twice.
func jsonDocumentTokens(in units: [UInt16]) -> [JSONToken]? {
    var parser = JSONParser(units, recordingTokens: true)
    parser.skipWhitespace()
    guard parser.parseValue() != nil else { return nil }
    parser.skipWhitespace()
    return parser.isAtEnd ? parser.tokens : nil
}

/// A strict recursive-descent parser over UTF-16 code units, so positions line up
/// with `NSRange`. It can record the tokens it reads, for syntax coloring.
private struct JSONParser {
    /// Deeper nesting fails the parse instead of overflowing the stack.
    static let maxDepth = 512

    let units: [UInt16]
    private(set) var position: Int
    private var depth = 0
    private let recordsTokens: Bool
    /// The tokens read so far, when recording; each is added once it has parsed whole.
    private(set) var tokens: [JSONToken] = []

    init(_ units: [UInt16], at position: Int = 0, recordingTokens: Bool = false) {
        self.units = units
        self.position = position
        recordsTokens = recordingTokens
    }

    /// Records a token from `start` to the current position.
    private mutating func record(_ kind: JSONTokenKind, from start: Int) {
        guard recordsTokens else { return }
        tokens.append(JSONToken(range: NSRange(location: start, length: position - start), kind: kind))
    }

    /// Advances past the punctuation `scalar` if it is the next code unit, recording it.
    private mutating func consumePunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let start = position
        guard consume(ascii: scalar) else { return false }
        record(.punctuation, from: start)
        return true
    }

    var isAtEnd: Bool { position >= units.count }

    private var current: UInt16? { isAtEnd ? nil : units[position] }

    mutating func skipWhitespace() {
        while let unit = current, unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09 {
            position += 1
        }
    }

    mutating func parseValue() -> JSONValue? {
        let start = position
        let value: JSONValue?
        let kind: JSONTokenKind
        switch current {
        case ascii("{"): return parseContainer(Self.parseObjectBody)
        case ascii("["): return parseContainer(Self.parseArrayBody)
        case ascii("\""): (value, kind) = (parseString().map(JSONValue.string), .string)
        case ascii("t"): (value, kind) = (consume("true") ? .bool(true) : nil, .boolean)
        case ascii("f"): (value, kind) = (consume("false") ? .bool(false) : nil, .boolean)
        case ascii("n"): (value, kind) = (consume("null") ? .null : nil, .null)
        default: (value, kind) = (parseNumber(), .number)
        }
        if value != nil { record(kind, from: start) }
        return value
    }

    private mutating func parseContainer(_ body: (inout JSONParser) -> JSONValue?) -> JSONValue? {
        guard depth < Self.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        position += 1  // the opening bracket
        record(.punctuation, from: position - 1)
        return body(&self)
    }

    private static func parseObjectBody(_ parser: inout JSONParser) -> JSONValue? {
        var entries: [JSONEntry] = []
        parser.skipWhitespace()
        if parser.consumePunctuation("}") { return .object(entries) }
        while true {
            parser.skipWhitespace()
            let keyStart = parser.position
            guard parser.current == ascii("\""), let key = parser.parseString() else { return nil }
            parser.record(.key, from: keyStart)
            parser.skipWhitespace()
            guard parser.consumePunctuation(":") else { return nil }
            parser.skipWhitespace()
            guard let value = parser.parseValue() else { return nil }
            entries.append(JSONEntry(key: key, value: value))
            parser.skipWhitespace()
            if parser.consumePunctuation("}") { return .object(entries) }
            guard parser.consumePunctuation(",") else { return nil }
        }
    }

    private static func parseArrayBody(_ parser: inout JSONParser) -> JSONValue? {
        var elements: [JSONValue] = []
        parser.skipWhitespace()
        if parser.consumePunctuation("]") { return .array(elements) }
        while true {
            parser.skipWhitespace()
            guard let value = parser.parseValue() else { return nil }
            elements.append(value)
            parser.skipWhitespace()
            if parser.consumePunctuation("]") { return .array(elements) }
            guard parser.consumePunctuation(",") else { return nil }
        }
    }

    /// Parses a string literal at the current `"`, decoding escapes.
    private mutating func parseString() -> String? {
        position += 1  // the opening quote
        var decoded: [UInt16] = []
        while let unit = current {
            position += 1
            switch unit {
            case ascii("\""):
                return String(decoding: decoded, as: UTF16.self)
            case ascii("\\"):
                guard let escaped = current else { return nil }
                position += 1
                switch escaped {
                case ascii("\""), ascii("\\"), ascii("/"): decoded.append(escaped)
                case ascii("b"): decoded.append(0x08)
                case ascii("f"): decoded.append(0x0C)
                case ascii("n"): decoded.append(0x0A)
                case ascii("r"): decoded.append(0x0D)
                case ascii("t"): decoded.append(0x09)
                case ascii("u"):
                    // Surrogate pairs arrive as two escapes; decoding the UTF-16 joins them.
                    guard let codeUnit = parseHex4() else { return nil }
                    decoded.append(codeUnit)
                default:
                    return nil
                }
            case 0..<0x20:
                return nil
            default:
                decoded.append(unit)
            }
        }
        return nil
    }

    private mutating func parseHex4() -> UInt16? {
        guard position + 4 <= units.count else { return nil }
        var value: UInt16 = 0
        for unit in units[position..<position + 4] {
            guard let digit = hexDigit(unit) else { return nil }
            value = value << 4 | digit
        }
        position += 4
        return value
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, kept as source text.
    private mutating func parseNumber() -> JSONValue? {
        let start = position
        _ = consume(ascii: "-")
        if consume(ascii: "0") {
            // No leading zeros.
        } else if consumeDigits() == 0 {
            return nil
        }
        if consume(ascii: "."), consumeDigits() == 0 { return nil }
        if current == ascii("e") || current == ascii("E") {
            position += 1
            if !consume(ascii: "+") { _ = consume(ascii: "-") }
            if consumeDigits() == 0 { return nil }
        }
        return .number(String(decoding: units[start..<position], as: UTF16.self))
    }

    private mutating func consumeDigits() -> Int {
        let start = position
        while let unit = current, unit >= ascii("0"), unit <= ascii("9") { position += 1 }
        return position - start
    }

    /// Advances past `scalar` if it is the next code unit.
    private mutating func consume(ascii scalar: Unicode.Scalar) -> Bool {
        guard current == UInt16(scalar.value) else { return false }
        position += 1
        return true
    }

    /// Advances past `literal` if the input continues with it.
    private mutating func consume(_ literal: String) -> Bool {
        let literalUnits = Array(literal.utf16)
        guard position + literalUnits.count <= units.count,
              units[position..<position + literalUnits.count].elementsEqual(literalUnits)
        else { return false }
        position += literalUnits.count
        return true
    }
}

/// The UTF-16 code unit of an ASCII scalar.
private func ascii(_ scalar: Unicode.Scalar) -> UInt16 {
    UInt16(scalar.value)
}

private func hexDigit(_ unit: UInt16) -> UInt16? {
    switch unit {
    case ascii("0")...ascii("9"): unit - ascii("0")
    case ascii("a")...ascii("f"): unit - ascii("a") + 10
    case ascii("A")...ascii("F"): unit - ascii("A") + 10
    default: nil
    }
}

/// The ranges of the JSON objects and arrays anywhere in `input`: every `{` or `[`
/// starts a parse attempt; a success becomes a range and scanning resumes after it,
/// a failure moves on by one code unit.
func jsonRanges(in input: String) -> [NSRange] {
    let units = Array(input.utf16)
    var ranges: [NSRange] = []
    var offset = 0
    while offset < units.count {
        let unit = units[offset]
        if unit == ascii("{") || (unit == ascii("[") && !followsIndexable(units, at: offset)),
           let scanned = JSONValue.scan(units, at: offset), scanned.value.isNonEmptyContainer {
            ranges.append(NSRange(location: offset, length: scanned.length))
            offset += scanned.length
        } else {
            offset += 1
        }
    }
    return ranges
}

/// Whether the `[` at `offset` reads as index syntax (`items[0]`, `call()[0]`,
/// `matrix[1][2]`): it directly follows an identifier character or a closing
/// bracket, so it subscripts what precedes it rather than starting JSON.
private func followsIndexable(_ units: [UInt16], at offset: Int) -> Bool {
    guard offset > 0, let previous = Unicode.Scalar(units[offset - 1]) else { return false }
    return previous == "_" || previous == "$" || previous == ")" || previous == "]"
        || previous.properties.isAlphabetic || ("0"..."9").contains(previous)
}

extension JSONValue {
    /// Whether this is an object or an array.
    public var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// An object or array with something in it; `{}` and `[]` carry nothing worth a
    /// Match or an inline parse.
    public var isNonEmptyContainer: Bool {
        switch self {
        case .object(let entries): !entries.isEmpty
        case .array(let elements): !elements.isEmpty
        default: false
        }
    }

    /// `text` parsed as one JSON object or array, or nil when it's anything else.
    public static func container(from text: String) -> JSONValue? {
        guard let value = parse(text), value.isContainer else { return nil }
        return value
    }
}
