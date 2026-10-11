import Foundation
import Synchronization

/// A regex Pattern's regex as `detect` runs it: Perl-style source rewritten for
/// ICU and compiled (ADR-0004).
public struct CompiledRegex: @unchecked Sendable {
    public let regex: NSRegularExpression
    /// The named groups, in group order: each a Field of every Match.
    public let fields: [FieldName]
}

/// A Field as the regex declares it: the name as written, its grok type, and the
/// ICU group that captures it.
public struct FieldName: Sendable, Equatable {
    public var name: String
    /// `int` or `float` from `%{NAME:field:type}`; a label only, values aren't converted.
    public var type: String?
    /// ICU only accepts `[A-Za-z][A-Za-z0-9]*` as a group name, so every named
    /// group is renamed to this.
    public var group: String
}

/// Why a regex can't be used, in words that name the cause.
public struct RegexError: Error, Sendable, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    /// U+0001 marks the groups grok references make, so a regex can't contain it.
    static let controlCharacter = RegexError("control character U+0001 isn't allowed in a regex")
}

/// Compiles a Pattern's regex, written in Perl-style regex (ADR-0004) with grok
/// references, or says why it can't be. This is the one place that decides what
/// a regex means: config loading, `detect` and Settings all compile through it.
/// Results are cached by source and definitions, so a Config's regexes compile
/// once, not on every pass.
///
/// First, grok: `%{NAME}` expands the Grok Definition `NAME` (one of `grok`, or
/// else a bundled one), recursively; `%{NAME:field}` also makes it a Field, and
/// `%{NAME:field:int}` or `:float` gives the Field a type. `\%{` stays literal.
/// An unknown name, a reference loop or another type is an error naming it.
///
/// Then, before ICU sees the source: the Python/PHP named-group spellings `(?P<n>…)`,
/// `(?'n'…)` and `(?P=n)` become ICU's; every named group gets an internal name,
/// and named backreferences (`\k<n>`, `\k'n'`, `\k{n}`, `\g{n}`) follow it;
/// `\g{-1}`, `\g{1}` and `\g1` become numbered backreferences, each in a group of
/// its own so a digit after one isn't read into its number; and a `{`
/// that doesn't start a quantifier, or a `}` that doesn't end one, is a literal,
/// as in Perl (`{,n}` means `{0,n}`). Character classes stay ICU's: an unescaped
/// `[` inside one opens a nested class, and a class that never closes because of
/// one is an error saying to write `\[`. Constructs ICU can't run are errors naming
/// them: `\K` (which ICU would read as a literal `K`), recursion and subroutine
/// calls, conditionals, branch reset, backtracking verbs and `(?^…)`. ICU's own
/// errors are reported with its reason and position in the regex as written.
///
/// `options` are ICU's matching options, such as `.caseInsensitive` for a Color
/// Rule's regex: they change what the regex matches, not how it's read.
public func compileRegex(
    _ source: String, grok: [GrokDefinition] = [], options: NSRegularExpression.Options = []
) -> Result<CompiledRegex, RegexError> {
    compile(source, grok: grok, within: nil, options: options)
}

/// Compiles a Grok Definition's body as `compileRegex` would, among the user's
/// definitions `grok` (and the bundled ones): errors point into the body, and a
/// loop is named from the definition itself.
public func compileGrokDefinition(_ definition: GrokDefinition, grok: [GrokDefinition]) -> Result<CompiledRegex, RegexError> {
    compile(definition.regex, grok: grok, within: definition.name)
}

private func compile(
    _ source: String, grok: [GrokDefinition], within definition: String?, options: NSRegularExpression.Options = []
) -> Result<CompiledRegex, RegexError> {
    let key = CacheKey(source: source, grok: grok, definition: definition, options: options.rawValue)
    if let cached = compiledRegexes.withLock({ $0[key] }) { return cached }
    let result = compileUncached(source, grok: grok, within: definition, options: options)
    compiledRegexes.withLock { cache in
        // Settings compiles a draft on every keystroke; don't keep them all.
        if cache.count >= 2000 { cache.removeAll() }
        cache[key] = result
    }
    return result
}

private struct CacheKey: Hashable {
    var source: String
    var grok: [GrokDefinition]
    var definition: String?
    var options: UInt
}

private let compiledRegexes = Mutex<[CacheKey: Result<CompiledRegex, RegexError>]>([:])

private let bundledGrok = Dictionary(GrokDefinition.bundled.map { ($0.name, $0.regex) }, uniquingKeysWith: { first, _ in first })

private func compileUncached(
    _ source: String, grok: [GrokDefinition], within definition: String?, options: NSRegularExpression.Options
) -> Result<CompiledRegex, RegexError> {
    let expanded: GrokExpansion
    let rewritten: PerlRewrite
    do {
        let definitions = bundledGrok.merging(grok.map { ($0.name, $0.regex) }) { _, user in user }
        expanded = try GrokExpansion(Array(source.utf16), definitions: definitions, within: definition)
        rewritten = try PerlRewrite(expanded.units, grokFields: expanded.fields)
    } catch let error as RegexError {
        return .failure(error)
    } catch {
        return .failure(RegexError("\(error)"))
    }
    let icuSource = String(decoding: rewritten.output, as: UTF16.self)
    do {
        return .success(CompiledRegex(regex: try NSRegularExpression(pattern: icuSource, options: options), fields: rewritten.fields))
    } catch {
        // Which top-level grok reference the expanded source's `unit` came from; nil
        // for one written in the regex itself.
        func reference(containing unit: Int) -> Int? {
            expanded.references.firstIndex { $0.range.contains(unit) }
        }
        // Where the expanded source's `unit` is in the regex as written, for a message.
        func location(of unit: Int) -> String {
            let reference = reference(containing: unit).map { " in \(expanded.references[$0].text)" } ?? ""
            let position = expanded.origins.isEmpty ? 0 : expanded.origins[min(unit, expanded.origins.count - 1)]
            return reference + " (at character \(position + 1))"
        }
        guard let failure = ICUDiagnosis.diagnose(icuSource) else { return .failure(RegexError("invalid regex")) }
        // ICU only says the class never closes, at the end of the regex; the cause is
        // usually a `[` meant as a literal, which opened a nested class (ADR-0004).
        // Only when that `[` is written in the same text as the class it's in: a
        // definition's own class inside a class the regex left open isn't the cause.
        if failure.status == ICUDiagnosis.unclosedClass, let unclosed = rewritten.unclosedClass {
            let inSameText = reference(containing: unclosed.opening)
            if let nested = unclosed.nested.first(where: { reference(containing: $0) == inSameText }) {
                return .failure(RegexError(
                    #"unescaped [ inside a character class starts a nested class; write \["# + location(of: nested)
                ))
            }
            // Otherwise the class itself is the one left open.
            return .failure(RegexError(failure.reason + location(of: unclosed.opening)))
        }
        guard failure.offset > 0 else { return .failure(RegexError(failure.reason)) }
        return .failure(RegexError(failure.reason + location(of: rewritten.origin(ofOutput: failure.offset - 1))))
    }
}

// MARK: Expanding grok

/// The source with every `%{…}` replaced by its definition's body, expanded.
private struct GrokExpansion {
    private(set) var units: [UInt16] = []
    /// For each unit, the source unit it came from: a reference's `%` for all of
    /// its expansion.
    private(set) var origins: [Int] = []
    /// Each top-level reference: its units in `units`, and how it's written.
    private(set) var references: [(range: Range<Int>, text: String)] = []
    /// The Fields grok references make, in the order their groups open; their
    /// groups are named `\u{1}` and their index here, for `PerlRewrite`.
    private(set) var fields: [(name: String, type: String?)] = []
    private let definitions: [String: String]

    /// `within` is the definition `source` is the body of, so a loop back to it is caught.
    init(_ source: [UInt16], definitions: [String: String], within definition: String? = nil) throws {
        guard !source.contains(1) else { throw RegexError.controlCharacter }
        self.definitions = definitions
        var index = 0
        while index < source.count {
            if let reference = Reference(in: source, at: index) {
                let start = units.count
                units += try expand(reference, stack: definition.map { [$0] } ?? [])
                origins += Array(repeating: index, count: units.count - start)
                references.append((start..<units.count, reference.text))
                index = reference.end
            } else {
                // An escape is two units, so `\%{` never starts a reference.
                let length = source[index] == ascii("\\") && index + 1 < source.count ? 2 : 1
                units += source[index..<index + length]
                origins += index..<index + length
                index += length
            }
        }
    }

    /// The body of `reference`, expanded, as a group: named for a Field, else not capturing.
    private mutating func expand(_ reference: Reference, stack: [String]) throws -> [UInt16] {
        if let start = stack.firstIndex(of: reference.name) {
            throw RegexError("grok definitions loop: " + (stack[start...] + [reference.name]).joined(separator: " → "))
        }
        guard let body = definitions[reference.name] else {
            throw RegexError("unknown grok definition \(reference.name)")
        }
        if let type = reference.type, type != "int", type != "float" {
            throw RegexError(#"grok type "\#(type)" in \#(reference.text) isn't int or float"#)
        }
        var opening = "(?:"
        if let field = reference.field {
            opening = "(?<\u{1}\(fields.count)>"
            fields.append((field, reference.type))
        }
        return Array(opening.utf16) + (try expand(Array(body.utf16), stack: stack + [reference.name])) + [ascii(")")]
    }

    private mutating func expand(_ body: [UInt16], stack: [String]) throws -> [UInt16] {
        guard !body.contains(1) else { throw RegexError.controlCharacter }
        var output: [UInt16] = []
        var index = 0
        while index < body.count {
            if let reference = Reference(in: body, at: index) {
                output += try expand(reference, stack: stack)
                index = reference.end
            } else {
                let length = body[index] == ascii("\\") && index + 1 < body.count ? 2 : 1
                output += body[index..<index + length]
                index += length
            }
        }
        return output
    }

    /// `%{NAME}`, `%{NAME:field}` or `%{NAME:field:type}`.
    private struct Reference {
        var name: String
        var field: String?
        var type: String?
        var text: String
        /// Just past the closing `}`.
        var end: Int

        init?(in source: [UInt16], at index: Int) {
            guard index + 1 < source.count, source[index] == ascii("%"), source[index + 1] == ascii("{"),
                  let close = (index + 2..<source.count).first(where: { source[$0] == ascii("}") })
            else { return nil }
            let parts = String(decoding: source[index + 2..<close], as: UTF16.self)
                .split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard GrokDefinition.isValidName(parts[0]), parts.dropFirst().allSatisfy({ !$0.isEmpty }) else { return nil }
            name = parts[0]
            field = parts.count > 1 ? parts[1] : nil
            type = parts.count > 2 ? parts[2] : nil
            text = String(decoding: source[index...close], as: UTF16.self)
            end = close + 1
        }
    }
}

// MARK: Rewriting Perl for ICU

/// One pass over the regex as written, producing ICU's spelling of it.
private struct PerlRewrite {
    private(set) var output: [UInt16] = []
    /// For each output unit, the index of the source unit it came from.
    private var origins: [Int] = []
    private(set) var fields: [FieldName] = []

    private let source: [UInt16]
    private let grokFields: [(name: String, type: String?)]
    private var index = 0
    /// Capture groups opened so far, named or not: ICU numbers them in this order.
    private var groupCount = 0
    /// Set once a `(?x)` flag turns on extended mode, where `#` starts a comment.
    /// Flags are scoped in Perl; treating the rest of the regex as extended is
    /// close enough to keep group-like text in comments alone.
    private var extended = false
    /// Named backreferences, resolved once every group is known: where in `output`
    /// the reference goes, and the name as written.
    private var backreferences: [(at: Int, name: String, origin: Int)] = []
    /// A character class that never closes: the `[` that opened it, and each
    /// unescaped `[` inside it that isn't a POSIX class like `[:alpha:]`, which
    /// opened a nested class where Perl would have read a literal `[`.
    private(set) var unclosedClass: (opening: Int, nested: [Int])?

    init(_ source: [UInt16], grokFields: [(name: String, type: String?)]) throws {
        self.source = source
        self.grokFields = grokFields
        while index < source.count {
            try step()
        }
        try resolveBackreferences()
    }

    /// The source position behind the output unit at `offset`.
    func origin(ofOutput offset: Int) -> Int {
        origins.isEmpty ? 0 : origins[min(offset, origins.count - 1)]
    }

    // MARK: Scanning

    private mutating func step() throws {
        switch source[index] {
        case ascii("\\"): try escape()
        case ascii("["): characterClass()
        case ascii("("): try group()
        case ascii("{"): brace()
        case ascii("}"): emit(#"\}"#, from: index); index += 1
        case ascii("#") where extended:
            let end = firstIndex(of: "\n", from: index) ?? source.count
            copy(end - index)
        default: copy(1)
        }
    }

    private mutating func escape() throws {
        let start = index
        guard index + 1 < source.count else { return copy(1) }
        switch source[index + 1] {
        case ascii("K"):
            throw RegexError(#"\K isn't supported"#)
        case ascii("Q"):
            // Quoted text runs to `\E` (or the end) and is ICU's to read.
            var end = index + 2
            while end < source.count, !(source[end] == ascii("\\") && end + 1 < source.count && source[end + 1] == ascii("E")) {
                end += 1
            }
            copy(min(end + 2, source.count) - index)
        case ascii("k"):
            index += 2
            guard let name = delimitedName(opening: ["<": ">", "'": "'", "{": "}"]) else {
                index = start
                return copy(2)
            }
            backreference(to: name, from: start)
        case ascii("g"):
            try gReference()
        case ascii("p"), ascii("P"), ascii("x"), ascii("N"), ascii("b"), ascii("B"), ascii("o"):
            // `\p{…}` and kin: the braces are part of the escape.
            if index + 2 < source.count, source[index + 2] == ascii("{"), let close = firstIndex(of: "}", from: index + 3) {
                copy(close + 1 - index)
            } else {
                copy(2)
            }
        default:
            copy(2)
        }
    }

    /// `\g{name}`, `\g{-1}`, `\g{1}`, `\g1`, `\g-1`; `\g<…>` and `\g'…'` are
    /// Oniguruma's subroutine calls.
    private mutating func gReference() throws {
        let start = index
        index += 2
        if index < source.count, source[index] == ascii("<") || source[index] == ascii("'") {
            let close: Character = source[index] == ascii("<") ? ">" : "'"
            let end = firstIndex(of: close, from: index + 1) ?? source.count - 1
            throw RegexError("subroutine call \(text(start..<min(end + 1, source.count))) isn't supported")
        }
        let reference: String
        if let braced = delimitedName(opening: ["{": "}"]) {
            reference = braced
        } else {
            var end = index
            if end < source.count, source[end] == ascii("-") { end += 1 }
            while end < source.count, isDigit(source[end]) { end += 1 }
            reference = text(index..<end)
            index = end
        }
        guard let number = Int(reference) else {
            if reference.isEmpty { throw RegexError(#"\g needs a group"#) }
            return backreference(to: reference, from: start)
        }
        let absolute = number < 0 ? groupCount + 1 + number : number
        guard absolute > 0 else { throw RegexError(#"\g{\#(reference)} refers to a group before the first"#) }
        // A group of its own, so a digit after it stays a literal: `\g{1}0` isn't `\10`.
        emit("(?:\\\(absolute))", from: start)
    }

    /// A character class, copied as is to its closing `]`; nothing inside one is a
    /// group or a quantifier. An unescaped `[` inside a class opens a nested class,
    /// as ICU and Oniguruma read it, rather than standing for itself as in Perl
    /// (ADR-0004), so the class closes at the `]` that balances it.
    private mutating func characterClass() {
        var end = index + 1
        var depth = 1
        var nested: [Int] = []
        if end < source.count, source[end] == ascii("^") { end += 1 }
        if end < source.count, source[end] == ascii("]") { end += 1 }
        while end < source.count, depth > 0 {
            switch source[end] {
            case ascii("\\"): end += 1
            case ascii("["):
                depth += 1
                let posix = end + 1 < source.count && source[end + 1] == ascii(":")
                if !posix { nested.append(end) }
            case ascii("]"): depth -= 1
            default: break
            }
            end += 1
        }
        if depth > 0 { unclosedClass = (opening: index, nested: nested) }
        copy(min(end, source.count) - index)
    }

    private mutating func group() throws {
        let start = index
        let next = index + 1 < source.count ? source[index + 1] : 0
        if next == ascii("*") {
            let end = firstIndex(of: ")", from: index) ?? source.count - 1
            throw RegexError("backtracking verb \(text(start..<end + 1)) isn't supported")
        }
        guard next == ascii("?") else {
            groupCount += 1
            return copy(1)
        }
        let rest = text(index + 2..<min(index + 4, source.count))
        if rest.hasPrefix("P<") || (rest.hasPrefix("<") && !rest.hasPrefix("<=") && !rest.hasPrefix("<!"))
            || rest.hasPrefix("'") {
            return try namedGroup()
        }
        if rest.hasPrefix("P=") {
            index += 3
            guard let name = delimitedName(opening: ["=": ")"]) else { throw RegexError("unclosed (?P=") }
            return backreference(to: name, from: start)
        }
        if rest.hasPrefix("P>") || rest.hasPrefix("&") || rest.hasPrefix("R") || rest.first.map(isCallStart) == true {
            let end = firstIndex(of: ")", from: index) ?? source.count - 1
            let call = text(start..<end + 1)
            if call == "(?R)" || call == "(?0)" { throw RegexError("recursion \(call) isn't supported") }
            throw RegexError("subroutine call \(call) isn't supported")
        }
        if rest.hasPrefix("(") { throw RegexError("conditionals (?(…)…) aren't supported") }
        if rest.hasPrefix("|") { throw RegexError("branch reset (?|…) isn't supported") }
        if rest.hasPrefix("^") { throw RegexError("(?^…) isn't supported") }
        if rest.hasPrefix("#") {
            // A comment: copied to its `)`, which isn't a group's.
            let end = firstIndex(of: ")", from: index) ?? source.count - 1
            return copy(end + 1 - index)
        }
        let flags = text(index + 2..<(firstIndex(of: ")", from: index) ?? source.count)).prefix { $0.isLetter || $0 == "-" }
        if flags.prefix(while: { $0 != "-" }).contains("x") { extended = true }
        copy(2)
    }

    private func isCallStart(_ character: Character) -> Bool {
        character.isASCII && (character.isNumber || character == "+" || character == "-")
            && !(character == "-" && !nextIsDigit(after: index + 3))
    }

    private func nextIsDigit(after position: Int) -> Bool {
        position < source.count && isDigit(source[position])
    }

    /// `(?<n>`, `(?P<n>`, `(?'n'`: renamed for ICU, with the name as written kept.
    private mutating func namedGroup() throws {
        let start = index
        index += source[index + 2] == ascii("P") ? 3 : 2
        let opening = source[index]
        let close: Character = opening == ascii("'") ? "'" : ">"
        guard let end = firstIndex(of: close, from: index + 1) else {
            throw RegexError("unclosed group name \(text(start..<source.count))")
        }
        let name = text(index + 1..<end)
        guard !name.isEmpty else { throw RegexError("a named group needs a name") }
        groupCount += 1
        let group = "g\(groupCount)"
        if name.hasPrefix("\u{1}"),
           let grok = Int(name.dropFirst()).flatMap({ grokFields.indices.contains($0) ? grokFields[$0] : nil }) {
            fields.append(FieldName(name: grok.name, type: grok.type, group: group))
        } else {
            fields.append(FieldName(name: name, group: group))
        }
        emit("(?<\(group)>", from: start)
        index = end + 1
    }

    /// `{n}`, `{n,}`, `{n,m}` and `{,m}` are quantifiers; any other `{` is a literal.
    private mutating func brace() {
        let start = index
        var end = index + 1
        while end < source.count, isDigit(source[end]) { end += 1 }
        let minimum = text(index + 1..<end)
        var maximum: String?
        if end < source.count, source[end] == ascii(",") {
            let comma = end
            end += 1
            while end < source.count, isDigit(source[end]) { end += 1 }
            maximum = text(comma + 1..<end)
        }
        let closes = end < source.count && source[end] == ascii("}")
        guard closes, !minimum.isEmpty || maximum?.isEmpty == false else {
            emit(#"\{"#, from: start)
            index += 1
            return
        }
        emit("{\(minimum.isEmpty ? "0" : minimum)\(maximum.map { ",\($0)" } ?? "")}", from: start)
        index = end + 1
    }

    // MARK: Backreferences

    private mutating func backreference(to name: String, from start: Int) {
        backreferences.append((output.count, name, start))
    }

    /// Inserts each named backreference, last first so earlier positions hold.
    private mutating func resolveBackreferences() throws {
        for reference in backreferences.reversed() {
            guard let field = fields.first(where: { $0.name == reference.name }) else {
                throw RegexError(#"no group named "\#(reference.name)""#)
            }
            let units = Array(#"\k<\#(field.group)>"#.utf16)
            output.insert(contentsOf: units, at: reference.at)
            origins.insert(contentsOf: Array(repeating: reference.origin, count: units.count), at: reference.at)
        }
    }

    // MARK: Helpers

    /// At an opening delimiter in `opening`, the name up to its closer, with
    /// `index` moved past it; nil (and `index` unmoved) otherwise.
    private mutating func delimitedName(opening: [Character: Character]) -> String? {
        guard index < source.count, let open = Unicode.Scalar(source[index]),
              let close = opening[Character(open)], let end = firstIndex(of: close, from: index + 1)
        else { return nil }
        let name = text(index + 1..<end)
        index = end + 1
        return name
    }

    private func firstIndex(of character: Character, from start: Int) -> Int? {
        let unit = ascii(character)
        return (start..<source.count).first { source[$0] == unit }
    }

    private func text(_ range: Range<Int>) -> String {
        String(decoding: source[max(0, range.lowerBound)..<min(range.upperBound, source.count)], as: UTF16.self)
    }

    private mutating func copy(_ count: Int) {
        let end = min(index + count, source.count)
        output.append(contentsOf: source[index..<end])
        origins.append(contentsOf: index..<end)
        index = end
    }

    private mutating func emit(_ string: String, from origin: Int) {
        let units = Array(string.utf16)
        output.append(contentsOf: units)
        origins.append(contentsOf: Array(repeating: origin, count: units.count))
    }
}

private func ascii(_ character: Character) -> UInt16 {
    UInt16(character.asciiValue!)
}

private func isDigit(_ unit: UInt16) -> Bool {
    (ascii("0")...ascii("9")).contains(unit)
}

// MARK: ICU's reasons

/// Asks ICU itself why a regex doesn't compile: `NSRegularExpression` only says
/// that it doesn't. `uregex_open` is looked up in the system's ICU at run time.
private enum ICUDiagnosis {
    /// `U_REGEX_MISSING_CLOSE_BRACKET`: a `[` set that never closes.
    static let unclosedClass: Int32 = 66319

    struct Failure {
        /// ICU's `U_REGEX_*` error code.
        var status: Int32
        var reason: String
        /// UTF-16 offset in the ICU source just past where ICU gave up; 0 when unknown.
        var offset: Int
    }

    private typealias Open = @convention(c) (
        UnsafePointer<UInt16>, Int32, UInt32, UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>
    ) -> OpaquePointer?
    private typealias Close = @convention(c) (OpaquePointer) -> Void
    private typealias ErrorName = @convention(c) (Int32) -> UnsafePointer<CChar>

    private struct Functions: @unchecked Sendable {
        var open: Open
        var close: Close
        var errorName: ErrorName
    }

    private static let functions: Functions? = {
        guard let library = dlopen("/usr/lib/libicucore.A.dylib", RTLD_LAZY),
              let open = dlsym(library, "uregex_open"), let close = dlsym(library, "uregex_close"),
              let errorName = dlsym(library, "u_errorName")
        else { return nil }
        return Functions(
            open: unsafeBitCast(open, to: Open.self), close: unsafeBitCast(close, to: Close.self),
            errorName: unsafeBitCast(errorName, to: ErrorName.self)
        )
    }()

    static func diagnose(_ pattern: String) -> Failure? {
        guard let functions else { return nil }
        // UParseError: line and offset (int32 each), then two 16-unit contexts.
        // Matching options don't change whether or where a regex fails to parse.
        let parseError = UnsafeMutableRawPointer.allocate(byteCount: 72, alignment: 4)
        defer { parseError.deallocate() }
        parseError.initializeMemory(as: UInt8.self, repeating: 0, count: 72)
        var status: Int32 = 0
        let units = Array(pattern.utf16) + [0]
        let regex = units.withUnsafeBufferPointer {
            functions.open($0.baseAddress!, Int32(units.count - 1), 0, parseError, &status)
        }
        if let regex { functions.close(regex) }
        guard status > 0 else { return nil }
        let reason = reasons[status] ?? String(cString: functions.errorName(status))
        let line = Int(parseError.load(fromByteOffset: 0, as: Int32.self))
        let column = Int(parseError.load(fromByteOffset: 4, as: Int32.self))
        return Failure(status: status, reason: reason, offset: offset(line: line, column: column, in: units.dropLast()))
    }

    /// ICU's position as a UTF-16 offset: it counts code points into a line (from
    /// 1), starting lines as its pattern scanner does: at CR, NEL, LS, and LF unless
    /// it follows CR; a line's break isn't one of its code points. 0 when ICU
    /// doesn't know the position (line 0 or below, or column -1).
    private static func offset(line: Int, column: Int, in units: ArraySlice<UInt16>) -> Int {
        guard line > 0, column >= 0 else { return 0 }
        var (currentLine, currentColumn) = (1, 0)
        var index = units.startIndex
        var last: UInt16 = 0
        while index < units.endIndex, currentLine < line || (currentLine == line && currentColumn < column) {
            let unit = units[index]
            let isPair = UTF16.isLeadSurrogate(unit) && index + 1 < units.endIndex
                && UTF16.isTrailSurrogate(units[index + 1])
            if unit == 0x0D || unit == 0x85 || unit == 0x2028 || (unit == 0x0A && last != 0x0D) {
                (currentLine, currentColumn) = (currentLine + 1, 0)
            } else if unit != 0x0A {
                currentColumn += 1
            }
            last = unit
            index += isPair ? 2 : 1
        }
        return index - units.startIndex
    }

    /// ICU's `U_REGEX_*` error codes in words.
    private static let reasons: [Int32: String] = [
        66305: "syntax error",
        66307: "unknown escape sequence",
        66308: #"bad \p{…} property"#,
        66309: "unsupported construct",
        66310: "unbalanced parenthesis",
        66311: "number too big",
        66312: "bad {…} repetition",
        66313: "{min,max} with max below min",
        66314: "backreference to a group that doesn't exist",
        66315: "unknown flag",
        66316: "lookbehind must have a bounded length",
        66317: "a [set] can't contain strings",
        66318: "octal value too big",
        66319: "unclosed [",
        66320: "bad range in [set]",
        66324: "regex too big",
        66325: "bad group name",
    ]
}
