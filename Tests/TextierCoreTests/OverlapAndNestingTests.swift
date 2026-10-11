import Foundation
import Testing
import TextierCore

@Suite("Overlap and nesting rules")
struct OverlapAndNestingTests {
    let first = Pattern(name: "first", regex: "abcd", actions: [.copy])
    let second = Pattern(name: "second", regex: "cdef", actions: [.copy])
    let longer = Pattern(name: "longer", regex: "cdefgh", actions: [.copy])

    @Test func partialOverlapKeepsOnlyTheLongerMatch() {
        let matches = detect("xx abcdefgh yy", config: Config(patterns: [first, longer]))

        #expect(matches.map(\.patternName) == ["longer"])
        #expect(matches.first?.children == [])
    }

    @Test func partialOverlapOfEqualLengthGoesToTheEarlierPatternInConfig() {
        #expect(detect("abcdef", config: Config(patterns: [first, second])).map(\.text) == ["abcd"])
        #expect(detect("abcdef", config: Config(patterns: [second, first])).map(\.text) == ["cdef"])
    }

    @Test func identicalRangesYieldOneMatchFromTheEarlierPattern() {
        let alsoURL = Pattern(name: "also url", regex: #"https?://\S+"#, actions: [.copy])
        let input = "go http://a.test/x now"

        let matches = detect(input, config: Config(patterns: [Preset.url, alsoURL]))
        #expect(matches.map(\.patternName) == ["url"])
        #expect(matches.first?.children == [])

        #expect(detect(input, config: Config(patterns: [alsoURL, Preset.url])).map(\.patternName) == ["also url"])
    }

    @Test func aLooseFilePathRegexOverlappingTheMonologURLLosesToTheLongerURL() {
        // Starts inside the URL and runs past its closing quote: a partial overlap.
        let loosePath = Pattern(name: "loose path", regex: #"/v1/signin","\w+"#, actions: [.copy])

        let matches = detect(Fixtures.monologLine, config: Config(patterns: [loosePath, Preset.url]))

        #expect(matches.map(\.text) == ["http://app.bo.test/player/api/v1/signin"])
    }

    @Test func disabledPatternsDoNotKnockOutOverlappingMatches() {
        var disabledLonger = longer
        disabledLonger.enabled = false

        #expect(detect("abcdefgh", config: Config(patterns: [disabledLonger, first])).map(\.text) == ["abcd"])
    }

    @Test func aMatchInsideAnotherBecomesItsChildAndIsNotTopLevel() throws {
        let input = "see https://a.test/feed?since=1696680000&x=1 and 1696680001"

        let matches = detect(input, config: .default)

        #expect(matches.map(\.text) == ["https://a.test/feed?since=1696680000&x=1", "1696680001"])
        let url = try #require(matches.first)
        #expect(url.children.map(\.text) == ["1696680000"])
        #expect(url.children.map(\.patternName) == ["datetime"])
        #expect(url.children.map(\.actions) == [[.copy]])
    }

    @Test func childRangesAreInInputCoordinates() throws {
        let input = "see https://a.test/feed?since=1696680000"

        let child = try #require(detect(input, config: .default).first?.children.first)

        #expect((input as NSString).substring(with: child.range) == child.text)
    }

    @Test func nestingIsRecursiveAndChildrenAreOrderedByPosition() throws {
        let angle = Pattern(name: "angle", regex: "<[^>]*>", actions: [.copy])
        let square = Pattern(name: "square", regex: #"\[[^\]]*\]"#, actions: [.copy])
        let input = "<at [2026-10-07 11:17:10] in /tmp/a.log> rest"

        let matches = detect(input, config: Config(patterns: [Preset.datetime, Preset.filePath, square, angle]))

        let outer = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(outer.patternName == "angle")
        #expect(outer.children.map(\.patternName) == ["square", "file path"])
        #expect(outer.children.first?.children.map(\.text) == ["2026-10-07 11:17:10"])
    }

    @Test func withoutTheJSONBuiltinNothingInTheMonologLineHasChildren() {
        let regexOnly = Config(patterns: Config.default.patterns.filter { $0.kind != .builtin(.json) })

        let matches = detect(Fixtures.monologLine, config: regexOnly)
        #expect(matches.map(\.patternName) == ["datetime", "url"] + Array(repeating: "file path", count: 6))
        #expect(matches.allSatisfy { $0.children.isEmpty })
    }

    @Test func emptyRegexMatchesAreIgnored() {
        let empty = Pattern(name: "empty", regex: "x*", actions: [.copy])

        #expect(detect("abc", config: Config(patterns: [empty])).isEmpty)
    }

    @Test func matchesAndTheirChildrenCarryTheirPatternsColor() throws {
        var json = Builtin.json
        json.color = "#e5c07b"
        var url = Preset.url
        url.color = "#61afef"
        let config = Config(patterns: [json, url, Preset.filePath])

        let matches = detect(Fixtures.monologLine, config: config)
        let jsonMatch = try #require(matches.first { $0.patternName == "json" })
        #expect(jsonMatch.color == "#e5c07b")
        #expect(jsonMatch.children.first { $0.patternName == "url" }?.color == "#61afef")
        #expect(jsonMatch.children.first { $0.patternName == "file path" }?.color == config.color(of: Preset.filePath))
    }
}
