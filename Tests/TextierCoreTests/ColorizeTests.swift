import Foundation
import Testing
import TextierCore

@Suite("Syntax coloring")
struct ColorizeTests {
    /// The Monolog context as the Inspector's Text mode shows it.
    let prettyMonolog = JSONValue.container(from: Fixtures.monologContextJSON)!.prettyPrinted

    /// A theme with one color per token kind, so each token's kind shows in its color.
    let distinct = try! Theme.load(Data(#"""
    { "tokenColors": [
      { "scope": "punctuation", "settings": { "foreground": "#000001" } },
      { "scope": "string", "settings": { "foreground": "#000002" } },
      { "scope": "support.type.property-name", "settings": { "foreground": "#000003" } },
      { "scope": "constant.numeric", "settings": { "foreground": "#000004" } },
      { "scope": "constant.language", "settings": { "foreground": "#000005", "fontStyle": "italic" } }
    ] }
    """#.utf8))

    /// Each colored range's text and kind, in order.
    func tokens(_ text: String, theme: Theme = .githubLight) -> [(String, JSONTokenKind)] {
        colorize(text, theme: theme).map { ((text as NSString).substring(with: $0.range), $0.kind) }
    }

    @Test func everyTokenGetsItsKind() {
        let found = tokens(#"{"a": [1, -2.5e3, "x", true, false, null], "b": {}}"#)

        #expect(found.map(\.0) == [
            "{", #""a""#, ":", "[", "1", ",", "-2.5e3", ",", #""x""#, ",", "true", ",", "false", ",", "null", "]", ",",
            #""b""#, ":", "{", "}", "}",
        ])
        #expect(found.map(\.1) == [
            .punctuation, .key, .punctuation, .punctuation, .number, .punctuation, .number, .punctuation, .string,
            .punctuation, .boolean, .punctuation, .boolean, .punctuation, .null, .punctuation, .punctuation,
            .key, .punctuation, .punctuation, .punctuation, .punctuation,
        ])
    }

    @Test func eachTokenTakesTheThemesStyleForItsKind() {
        let colored = colorize(#"{"a": [1, "x", true, null]}"#, theme: distinct)

        #expect(colored.map(\.style.color) == [
            "#000001", "#000003", "#000001", "#000001", "#000004", "#000001", "#000002", "#000001", "#000005",
            "#000001", "#000005", "#000001", "#000001",
        ])
        #expect(colored.first { $0.kind == .null }?.style.fontStyle == .italic)
    }

    @Test func theMonologJSONShowsKeysStringsNumbersAndLiteralsInDistinctColors() {
        let json = #"{"key": "string", "number": 1, "literal": true}"#
        for theme in [Theme.githubLight, Theme.githubDark] {
            let colored = colorize(prettyMonolog, theme: theme) + colorize(json, theme: theme)
            func colors(_ kind: JSONTokenKind) -> Set<String> {
                Set(colored.filter { $0.kind == kind }.map(\.style.color))
            }

            #expect(colors(.key).count == 1)
            #expect(colors(.string).count == 1)
            #expect(colors(.number).count == 1)
            #expect(colors(.boolean).count == 1)
            #expect(Set([colors(.key), colors(.string), colors(.number), colors(.punctuation)]).count == 4)
            // GitHub colors literals as constants, like numbers, as VS Code shows them.
            #expect(colors(.boolean) == colors(.number))
            #expect(colors(.boolean) != colors(.string) && colors(.boolean) != colors(.key))
        }
    }

    @Test func theMonologJSONIsCoveredWithoutGapsOverlapsOrColoredWhitespace() {
        assertCovers(prettyMonolog)
    }

    @Test func rangesAreUTF16() {
        let text = #"{"emoji 😀": "naïve ☕️", "n": 1}"#
        let found = tokens(text)

        #expect(found.map(\.0) == ["{", #""emoji 😀""#, ":", #""naïve ☕️""#, ",", #""n""#, ":", "1", "}"])
        assertCovers(text)
    }

    @Test func escapedJSONInsideAStringColorsAsTheString() {
        let text = #"{"context": "{\"user\":{\"id\":7}}"}"#
        let found = tokens(text)

        #expect(found.map(\.0) == ["{", #""context""#, ":", #""{\"user\":{\"id\":7}}""#, "}"])
        #expect(found[3].1 == .string)
    }

    @Test func aStringWithEscapesIsOneToken() {
        #expect(tokens(#"["a\"b\\cé\n"]"#).map(\.0) == ["[", #""a\"b\\cé\n""#, "]"])
    }

    @Test func aScalarDocumentIsColoredToo() {
        #expect(tokens(#"  "just a string"  "#).map(\.1) == [.string])
        #expect(tokens("42").map(\.1) == [.number])
    }

    /// Text that stops being JSON is colored up to where it stops; nothing after it is.
    @Test func invalidJSONIsColoredUpToWhereItStops() {
        #expect(tokens(#"{"a": 1, "b": tru}"#).map(\.0) == ["{", #""a""#, ":", "1", ",", #""b""#, ":"])
        #expect(tokens(#"{"a": 1} trailing"#).map(\.0) == ["{", #""a""#, ":", "1", "}"])
        #expect(tokens("not json").isEmpty)
        #expect(tokens("").isEmpty)
    }

    @Test func aUserThemeOverridingTheStringScopeChangesStringColors() throws {
        let theme = try Theme.load(Data(#"""
        { "tokenColors": [{ "scope": "string", "settings": { "foreground": "#ff00ff" } }] }
        """#.utf8))
        let strings = colorize(prettyMonolog, theme: theme).filter { $0.kind == .string }
        let defaults = colorize(prettyMonolog, theme: .githubLight).filter { $0.kind == .string }

        #expect(!strings.isEmpty)
        #expect(strings.allSatisfy { $0.style.color == "#ff00ff" })
        #expect(defaults.allSatisfy { $0.style.color != "#ff00ff" })
    }

    /// Ranges are in order, don't overlap, and together cover every character of
    /// `text` except whitespace between tokens.
    func assertCovers(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let colored = colorize(text, theme: .githubLight)
        let units = Array(text.utf16)
        var covered = [Bool](repeating: false, count: units.count)
        var end = 0
        for range in colored.map(\.range) {
            #expect(range.location >= end, "overlap or out of order at \(range)", sourceLocation: sourceLocation)
            #expect(range.length > 0, sourceLocation: sourceLocation)
            for offset in range.location..<NSMaxRange(range) { covered[offset] = true }
            end = NSMaxRange(range)
        }
        let whitespace: Set<UInt16> = [0x20, 0x0A, 0x0D, 0x09]
        for (offset, unit) in units.enumerated() where !covered[offset] {
            #expect(whitespace.contains(unit), "offset \(offset) is uncolored", sourceLocation: sourceLocation)
        }
        for range in colored.map(\.range) {
            #expect(!whitespace.contains(units[range.location]), sourceLocation: sourceLocation)
            #expect(!whitespace.contains(units[NSMaxRange(range) - 1]), sourceLocation: sourceLocation)
        }
    }
}
