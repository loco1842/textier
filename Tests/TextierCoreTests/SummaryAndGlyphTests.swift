import Foundation
import Testing
import TextierCore

/// The clock is `InspectionClock`: now is 2026-10-09 12:00:00 in UTC+7.
@Suite("Summaries: what a Match means, in one line")
struct SummaryTests {
    func summary(of name: String, _ index: Int = 0, in input: String, config: Config = .default) throws -> Summary? {
        let entries = inspectFixed(input, config: config).entries(.pattern(name))
        return try #require(entries.indices.contains(index) ? entries[index] : nil).summary
    }

    @Test func aDatetimeTodayIsItsLocalTimeAndAge() throws {
        let summary = try summary(of: "datetime", in: "at 2026-10-09T03:30:00Z")

        #expect(summary == Summary("10:30:00 · 1 hour ago"))
    }

    @Test func aDatetimeOnAnotherDayKeepsItsDate() throws {
        let summary = try summary(of: "datetime", in: "at 2026-10-09T10:00:00+02:00 and 2026-10-01T00:00:00Z")
        let other = try self.summary(of: "datetime", 1, in: "at 2026-10-09T10:00:00+02:00 and 2026-10-01T00:00:00Z")

        #expect(summary == Summary("15:00:00 · in 3 hours"))
        #expect(other == Summary("2026-10-01 07:00:00 · 8 days ago"))
    }

    @Test func anOffsetlessDatetimeCarriesBothReadings() throws {
        let summary = try #require(try summary(of: "datetime", in: Fixtures.monologLine))

        #expect(summary.text == "2026-10-07 11:17:10 · 2 days ago")
        #expect(summary.asUTC == "2026-10-07 18:17:10 · 1 day ago")
        #expect(summary.text(readsAsUTC: false) == summary.text)
        #expect(summary.text(readsAsUTC: true) == summary.asUTC)
    }

    @Test func anOffsetlessDatetimeTodayDropsTheDateInBothReadings() throws {
        let summary = try summary(of: "datetime", in: "at 2026-10-09 06:00:00")

        #expect(summary == Summary("06:00:00 · 6 hours ago", asUTC: "13:00:00 · in 1 hour"))
    }

    @Test func anEpochIsReadAsUTC() throws {
        #expect(try summary(of: "datetime", in: "t=1791522000") == Summary("12:00:00 · just now"))
    }

    @Test func aFilePathIsItsFileNameLineAndColumn() throws {
        let input = "/Users/dev/src/app.ts:142:17 and /tmp/a.log:12 and ~/notes.txt"

        #expect(try summary(of: "file path", 0, in: input) == Summary("app.ts · line 142, col 17"))
        #expect(try summary(of: "file path", 1, in: input) == Summary("a.log · line 12"))
        #expect(try summary(of: "file path", 2, in: input) == Summary("notes.txt"))
    }

    @Test func aBacktraceFrameTakesItsPairedLine() throws {
        #expect(try summary(of: "file path", 1, in: Fixtures.monologLine) == Summary("EmailTemplateService.php · line 80"))
    }

    @Test func aURLIsItsHost() throws {
        #expect(try summary(of: "url", in: "see https://dashboard.stripe.com/test/logs?x=1#y") == Summary("dashboard.stripe.com"))
    }

    @Test func aJSONObjectIsItsSizeAndFirstKeys() throws {
        let input = #"{"orderId":1,"amount":2,"currency":"EUR","retry":true} {"a":1,"b":2} {"a":1} {}"#

        #expect(try summary(of: "json", 0, in: input) == Summary("4 keys · orderId, amount, currency…"))
        #expect(try summary(of: "json", 1, in: input) == Summary("2 keys · a, b"))
        #expect(try summary(of: "json", 2, in: input) == Summary("1 key · a"))
    }

    @Test func aJSONArrayIsItsItemCount() throws {
        let input = "[1, 2, 3] and [true]"

        #expect(try summary(of: "json", 0, in: input) == Summary("3 items"))
        #expect(try summary(of: "json", 1, in: input) == Summary("1 item"))
    }

    @Test func aRegexPatternWithFieldsIsItsFirstThreeFields() throws {
        let request = Pattern(
            name: "request", regex: #"(?<client>\d+\.\d+\.\d+\.\d+) (?<method>[A-Z]+) (?<path>\S+) (?<status>\d{3})"#,
            actions: [.copy]
        )
        let config = Config(patterns: [request])

        #expect(try summary(of: "request", in: "10.0.0.4 GET /x 200", config: config)
            == Summary("client 10.0.0.4 · method GET · path /x"))
    }

    @Test func aRegexPatternWithOneFieldIsThatField() throws {
        let level = Pattern(name: "lvl", regex: #"level=(?<level>\w+)"#, actions: [.copy])

        #expect(try summary(of: "lvl", in: "level=warn", config: Config(patterns: [level])) == Summary("level warn"))
    }

    @Test func aLogLevelAUserPatternWithoutFieldsAndPlainTextHaveNone() throws {
        var config = Config.default
        config.patterns[5].enabled = true
        config.patterns.append(Pattern(name: "ticket", regex: #"JIRA-\d+"#, actions: [.copy]))
        let inspection = inspectFixed("ERROR in JIRA-12 again", config: config)

        #expect(inspection.entries(.pattern("log level")).map(\.summary) == [nil])
        #expect(inspection.entries(.pattern("ticket")).map(\.summary) == [nil])
        #expect(inspection.entries(.plainText).allSatisfy { $0.summary == nil })
        #expect(!inspection.entries(.plainText).isEmpty)
    }
}

@Suite("Glyphs: one mark per Pattern name")
struct GlyphTests {
    let userURL = Pattern(name: "url", regex: #"\bwww\.\S+"#, actions: [.copy])

    @Test func eachBuiltinAndPresetHasItsOwn() {
        let config = Config.default

        #expect(config.glyph(ofName: "json") == .json)
        #expect(config.glyph(ofName: "escaped-json") == .escapedJSON)
        #expect(config.glyph(ofName: "url") == .url)
        #expect(config.glyph(ofName: "datetime") == .datetime)
        #expect(config.glyph(ofName: "file path") == .filePath)
        #expect(config.glyph(ofName: "log level") == .logLevel)
        #expect(Set(Glyph.allCases).count == 8)
    }

    @Test func tabsCarryTheirGlyphAndPlainTextItsOwn() {
        let inspection = inspectFixed(Fixtures.monologLine)

        #expect(inspection.tabs.map(\.glyph) == [.datetime, .json, .url, .filePath, .plainText])
    }

    @Test func twoRegexPatternsNamedURLTakeTheURLGlyphInEitherOrder() {
        let presetFirst = Config(patterns: [Preset.url, userURL])
        let userFirst = Config(patterns: [userURL, Preset.url])

        #expect(presetFirst.glyph(ofName: "url") == .url)
        #expect(userFirst.glyph(ofName: "url") == .url)
        #expect(inspectFixed("go www.a.test", config: userFirst).tab(.pattern("url"))?.glyph == .url)
    }

    @Test func aUserPatternWithItsOwnNameTakesTheSharedUserGlyph() {
        let config = Config(patterns: Config.default.patterns + [
            Pattern(name: "ticket", regex: #"JIRA-\d+"#, actions: [.copy]),
            Pattern(name: "user", regex: #"@\w+"#, actions: [.copy]),
        ])

        #expect(config.glyph(ofName: "ticket") == .userPattern)
        #expect(config.glyph(ofName: "user") == .userPattern)
        #expect(inspectFixed("JIRA-1 by @ann", config: config).tabs.map(\.glyph) == [.userPattern, .userPattern, .plainText])
        #expect(Config(patterns: [Pattern(name: "json", regex: "x", actions: [.copy])]).glyph(ofName: "json") == .userPattern)
    }

    @Test func aNameTheConfigDoesntHaveIsReadByName() {
        let config = Config(patterns: [])

        #expect(config.glyph(ofName: "json") == .json)
        #expect(config.glyph(ofName: "datetime") == .datetime)
        #expect(config.glyph(ofName: "ticket") == .userPattern)
    }
}
