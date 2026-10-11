import Foundation

/// The line paired with an object's `file` value, as a Monolog backtrace frame
/// writes it (`{"file": "/…/Dispatcher.php", "line": 603}`), or nil.
///
/// The object's first `file` entry must be a string that's a file path Match in its
/// entirety (an `open-file` Pattern, per `stringValueMatch`) with no `:line` of its
/// own (the path's own line wins), and its first `line` entry a positive integer:
/// a number of digits only, or a string of digits only. Only those literal keys pair.
public func pairedLine(in entries: [JSONEntry], config: Config) -> Int? {
    pairedLine(
        file: entries.first { $0.key == "file" }?.value, line: entries.first { $0.key == "line" }?.value,
        config: config, budget: MatchingBudget()
    )
}

/// A `file` value paired with its line, found in JSON text.
public struct FileLineTarget: Sendable, Equatable {
    /// UTF-16 range of the `file` string's content in the text: inside the quotes,
    /// as written, escapes included.
    public var range: NSRange
    public var line: Int

    public init(range: NSRange, line: Int) {
        self.range = range
        self.line = line
    }
}

/// The paired `file` values in `text`, one JSON document, ordered by position:
/// `pairedLine(in:config:)` applied to every object in it. JSON escaped inside a
/// string value isn't structure in this text, so it isn't searched. Text that isn't
/// JSON has none.
public func fileLineTargets(in text: String, config: Config) -> [FileLineTarget] {
    fileLineTargets(in: text, config: config, budget: MatchingBudget())
}

/// `fileLineTargets`, matching the `file` values within `budget`.
func fileLineTargets(in text: String, config: Config, budget: MatchingBudget) -> [FileLineTarget] {
    let units = Array(text.utf16)
    guard let tokens = jsonDocumentTokens(in: units) else { return [] }
    /// The keys that matter; any other key's value is passed over unread.
    enum Key { case file, line, other }
    /// An open object or array, and what's been read of an object's `file` and `line`.
    struct Container {
        var isObject: Bool
        /// The key whose value comes next.
        var key: Key?
        /// The first `file` entry: its value (nil for a container) and token range.
        var file: (value: JSONValue?, range: NSRange)?
        /// The first `line` entry's value (nil inside for a container).
        var line: JSONValue??
    }
    func piece(_ range: NSRange) -> String {
        String(decoding: units[range.location..<NSMaxRange(range)], as: UTF16.self)
    }
    /// A key token's key, decoding it only when it's escaped.
    func key(_ range: NSRange) -> Key {
        let inside = units[(range.location + 1)..<(NSMaxRange(range) - 1)]
        let name: String
        if inside.contains(0x5C) {
            guard case .string(let decoded)? = JSONValue.parse(piece(range)) else { return .other }
            name = decoded
        } else {
            name = String(decoding: inside, as: UTF16.self)
        }
        return name == "file" ? .file : name == "line" ? .line : .other
    }
    var open: [Container] = []
    var targets: [FileLineTarget] = []
    /// Gives the value just read (nil for a container) to the innermost object's
    /// pending key, parsing it only if it's the first `file` or `line`.
    func read(at range: NSRange, isContainer: Bool) {
        guard let last = open.indices.last, open[last].isObject, let key = open[last].key else { return }
        open[last].key = nil
        func value() -> JSONValue? { isContainer ? nil : JSONValue.parse(piece(range)) }
        if key == .file, open[last].file == nil { open[last].file = (value(), range) }
        if key == .line, open[last].line == nil { open[last].line = .some(value()) }
    }
    for token in tokens {
        let first = units[token.range.location]
        switch token.kind {
        case .key:
            open[open.count - 1].key = key(token.range)
        case .punctuation where first == 0x7B || first == 0x5B: // { [
            read(at: token.range, isContainer: true)
            open.append(Container(isObject: first == 0x7B))
        case .punctuation where first == 0x7D || first == 0x5D: // } ]
            let closed = open.removeLast()
            if let file = closed.file,
               let line = pairedLine(file: file.value, line: closed.line ?? nil, config: config, budget: budget) {
                let content = NSRange(location: file.range.location + 1, length: file.range.length - 2)
                targets.append(FileLineTarget(range: content, line: line))
            }
        case .punctuation:
            break
        default:
            read(at: token.range, isContainer: false)
        }
    }
    return targets.sorted { $0.range.location < $1.range.location }
}

/// The pairing rule on an object's first `file` and `line` values.
private func pairedLine(file: JSONValue?, line: JSONValue?, config: Config, budget: MatchingBudget) -> Int? {
    guard case .string(let path)? = file, let line, isPairablePath(path, config: config, budget: budget) else {
        return nil
    }
    return positiveLine(line)
}

/// Whether `path` is a whole file path Match without a `:line` suffix.
private func isPairablePath(_ path: String, config: Config, budget: MatchingBudget) -> Bool {
    guard let match = stringValueMatch(path, config: config, budget: budget), match.actions.contains(.openFile)
    else { return false }
    return FileLocation(matchText: path, homeDirectory: "").line == nil
}

/// `80` or `"80"`; nil for `0`, negatives, fractions, exponents, other strings and
/// anything else.
private func positiveLine(_ value: JSONValue) -> Int? {
    let digits: String
    switch value {
    case .number(let source): digits = source
    case .string(let string): digits = string
    default: return nil
    }
    guard !digits.isEmpty, digits.utf8.allSatisfy({ (0x30...0x39).contains($0) }), let line = Int(digits), line > 0
    else { return nil }
    return line
}
