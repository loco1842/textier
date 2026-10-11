import Foundation
import Testing
import TextierCore

@Suite("URL Preset detection")
struct URLDetectionTests {
    let config = Config(patterns: [Preset.url])

    @Test func monologLineHasOneURLMatchEndingAtTheClosingQuote() {
        let matches = detect(Fixtures.monologLine, config: config)

        #expect(matches.map(\.text) == ["http://app.bo.test/player/api/v1/signin"])
    }

    @Test func matchRangeLocatesTheMatchTextInTheInput() throws {
        let match = try #require(detect(Fixtures.monologLine, config: config).first)

        #expect((Fixtures.monologLine as NSString).substring(with: match.range) == match.text)
    }

    @Test func urlMatchOffersOpenURLFirstThenCopy() throws {
        let match = try #require(detect(Fixtures.monologLine, config: config).first)

        #expect(match.patternName == "url")
        #expect(match.actions == [.openURL, .copy])
    }

    @Test(arguments: [
        ("see https://example.com/a?b=1&c=2#frag now", "https://example.com/a?b=1&c=2#frag"),
        ("open http://localhost:8080/health\nthen", "http://localhost:8080/health"),
        ("(http://example.com/x)", "http://example.com/x"),
        ("[http://example.com/x]", "http://example.com/x"),
        ("{http://example.com/x}", "http://example.com/x"),
        ("<http://example.com/x>", "http://example.com/x"),
        ("'http://example.com/x'", "http://example.com/x"),
        ("`http://example.com/x`", "http://example.com/x"),
        ("url=https://example.com/x\tnext", "https://example.com/x"),
    ])
    func urlEndsAtWhitespaceOrClosingQuoteOrBracket(input: String, expected: String) {
        #expect(detect(input, config: config).map(\.text) == [expected])
    }

    @Test(arguments: [
        ("see https://example.com/guide. Then", "https://example.com/guide"),
        ("is it https://example.com/x?", "https://example.com/x"),
        ("at https://example.com/x: done", "https://example.com/x"),
        ("wow https://example.com/x!", "https://example.com/x"),
        ("serve http://localhost:8080.", "http://localhost:8080"),
        ("go to https://example.com/a?b=1.", "https://example.com/a?b=1"),
        ("(see http://example.com/x).", "http://example.com/x"),
        ("version https://example.com/v1.2/notes.html;", "https://example.com/v1.2/notes.html"),
    ])
    func urlDoesNotEndOnTheSentencesPunctuation(input: String, expected: String) {
        #expect(detect(input, config: config).map(\.text) == [expected])
    }

    @Test func aCommaSeparatedListIsOneMatchPerURL() {
        let input = "https://a.test/1, https://b.test/2, and https://c.test/3."

        #expect(detect(input, config: config).map(\.text) == ["https://a.test/1", "https://b.test/2", "https://c.test/3"])
    }

    @Test func everyURLInTheInputIsAMatchInOrder() {
        let input = "GET https://a.test/1 -> 302 http://b.test/2"

        #expect(detect(input, config: config).map(\.text) == ["https://a.test/1", "http://b.test/2"])
    }

    @Test(arguments: [
        "ftp://example.com/file",
        "file:///Users/mac/file.txt",
        "http:/example.com",
        "http//example.com",
        "http://",
        "https:// example.com",
        "xhttp://example.com",
        "httpx://example.com",
        "example.com/path",
        "plain text with no links",
    ])
    func nearMissesAreNotMatches(input: String) {
        #expect(detect(input, config: config).isEmpty)
    }

    @Test func disabledPatternProducesNoMatches() {
        var url = Preset.url
        url.enabled = false

        #expect(detect(Fixtures.monologLine, config: Config(patterns: [url])).isEmpty)
    }
}
