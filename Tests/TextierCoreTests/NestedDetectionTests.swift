import Foundation
import Testing
import TextierCore

@Suite("Detection inside a Match Window")
struct NestedDetectionTests {
    @Test func prettyPrintedMonologPayloadHighlightsItsURLAndFilePaths() throws {
        let pretty = try #require(JSONValue.parse(Fixtures.monologContextJSON)).prettyPrinted

        let matches = detectNested(in: pretty, config: .default)

        #expect(matches.map(\.patternName) == ["url"] + Array(repeating: "file path", count: 6))
        #expect(matches.first?.actions == [.openURL, .copy])
        #expect(matches.allSatisfy { (pretty as NSString).substring(with: $0.range) == $0.text })
    }

    @Test func matchesThatDoNotSpanTheWholeTextAreKeptAsTheyAre() {
        let text = "see https://a.test/x and /tmp/a.log"

        #expect(detectNested(in: text, config: .default).map(\.text) == ["https://a.test/x", "/tmp/a.log"])
    }

    @Test func aURLMatchWindowShowsTheEpochInsideIt() {
        let text = "https://a.test/feed?since=1696680000"

        #expect(detectNested(in: text, config: .default).map(\.text) == ["1696680000"])
    }

    @Test func aMatchWithNothingInsideLeavesNothingToHighlight() {
        #expect(detectNested(in: "2026-10-07 11:17:10", config: .default).isEmpty)
    }
}
