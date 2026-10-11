import Foundation
import Testing
import TextierCore

/// Inspects with a fixed clock, zone and home, and no file on disk unless named.
func inspectFixed(
    _ input: String, config: Config = .default, previous: Inspection? = nil, existing: Set<String> = []
) -> Inspection {
    inspect(
        input, config: config, previous: previous, now: InspectionClock.now, timeZone: InspectionClock.zone,
        homeDirectory: "/Users/dev", fileExists: { existing.contains($0) }
    )
}

enum InspectionClock {
    /// 2026-10-09T05:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_791_522_000)
    /// UTC+7, no daylight saving.
    static let zone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
}

extension Inspection {
    /// The entries of the tab with `id`, empty when there's no such tab.
    func entries(_ id: InspectorTab.ID) -> [InspectorEntry] {
        tab(id)?.entries ?? []
    }
}

@Suite("Inspection tabs and entries")
struct InspectionTests {
    let monolog = inspectFixed(Fixtures.monologLine)

    @Test func monologTabsReadLikeTheLineThenPlainText() {
        #expect(monolog.tabs.map(\.id) == [
            .pattern("datetime"), .pattern("json"), .pattern("url"), .pattern("file path"), .plainText,
        ])
        #expect(monolog.tabs.map(\.title) == ["datetime", "json", "url", "file path", "Plain Text"])
        #expect(monolog.tabs.dropLast().map(\.entries.count) == [1, 1, 1, 6])
        #expect(monolog.showsInspector)
    }

    @Test func tabsCarryTheirPatternsResolvedColorAndPlainTextNone() {
        let config = Config.default
        #expect(monolog.tab(.pattern("json"))?.color == config.color(of: Builtin.json))
        #expect(monolog.tab(.pattern("url"))?.color == config.color(of: Preset.url))
        #expect(monolog.tab(.plainText)?.color == nil)
    }

    @Test func topLevelMatchesAreDetectsResult() {
        #expect(monolog.matches == detect(Fixtures.monologLine, config: .default))
    }

    @Test func entriesAreIndexedInPositionOrderWithTheirRangeTextAndActions() throws {
        let paths = monolog.entries(.pattern("file path"))
        #expect(paths.map(\.index) == Array(0..<6))
        #expect(paths.map(\.range.location) == paths.map(\.range.location).sorted())
        let line = Fixtures.monologLine as NSString
        for entry in paths {
            #expect(line.substring(with: entry.range) == entry.text)
            #expect(entry.actions == Preset.filePath.actions)
        }
        #expect(paths.first?.text.hasSuffix("SendLoginFromNewIPEmailToPlayer.php") == true)
    }

    @Test func nestedEntriesNameTheirTopLevelParent() {
        #expect(monolog.entries(.pattern("url")).map(\.parent?.description) == ["in json 0"])
        #expect(monolog.entries(.pattern("file path")).allSatisfy { $0.parent?.description == "in json 0" })
        #expect(monolog.entries(.pattern("json")).first?.parent == nil)
        #expect(monolog.entries(.pattern("datetime")).first?.parent == nil)
    }

    @Test func aMatchNestedTwoDeepStillNamesTheTopLevelMatch() {
        // The url sits in the inner object, which sits in the outer one; both are json.
        let input = #"first {"a":1} then {"outer":{"link":"https://a.test/x"}}"#
        let inspection = inspectFixed(input)

        let json = inspection.entries(.pattern("json"))
        #expect(json.map(\.text) == [#"{"a":1}"#, #"{"outer":{"link":"https://a.test/x"}}"#])
        #expect(inspection.entries(.pattern("url")).map(\.parent?.description) == ["in json 1"])
    }

    @Test func theLargestTopLevelMatchIsSelectedOnOpen() {
        #expect(monolog.selection == EntryID(tab: .pattern("json"), index: 0))
        #expect(monolog.selectedEntry?.text == Fixtures.monologContextJSON)
    }

    @Test func noMatchesMeansNoInspectorAndNoSelection() {
        let inspection = inspectFixed("just a log message")

        #expect(!inspection.showsInspector)
        #expect(inspection.selection == nil)
        #expect(inspection.tabs.map(\.id) == [.plainText])
    }

    @Test func emptyInputHasNoTabs() {
        #expect(inspectFixed("").tabs.isEmpty)
    }

    // MARK: Previews

    @Test func previewsAreOneLineWithWhitespaceCollapsed() {
        let input = "{\n  \"a\": \"b\",\n\t\"c\":   1\n}"
        let entry = inspectFixed(input).entries(.pattern("json")).first

        #expect(entry?.preview == #"{ "a": "b", "c": 1 }"#)
        #expect(entry?.text == input)
    }

    @Test func longPreviewsAreCutWithAnEllipsis() throws {
        let json = try #require(monolog.entries(.pattern("json")).first)

        #expect(json.preview.count == InspectorEntry.previewLength)
        #expect(json.preview.hasSuffix("…"))
        #expect(json.preview.hasPrefix(#"{"url":"http://app.bo.test"#))
        #expect(!json.preview.contains("\n"))
    }

    @Test func shortPreviewsAreTheTextItself() {
        #expect(monolog.entries(.pattern("datetime")).first?.preview == "2026-10-07 11:17:10")
    }

    // MARK: Plain Text

    @Test func plainTextIsTheLogMessageTrimmedWithoutPunctuationOnlyGaps() throws {
        let plain = monolog.entries(.plainText)

        #expect(plain.map(\.text) == [
            "develop.WARNING: [REPOSITORY SCOPE LEAK] __call invoked with non-empty scopeQueries",
        ])
        let entry = try #require(plain.first)
        #expect((Fixtures.monologLine as NSString).substring(with: entry.range) == entry.text)
        #expect(entry.actions == [.copy])
        #expect(entry.parent == nil)
        #expect(entry.detail == .text(entry.text))
        #expect(entry.index == 0)
    }

    @Test func plainTextListsEachGapAsItsOwnEntry() {
        let input = "start https://a.test/x middle (https://b.test/y), end."

        #expect(inspectFixed(input).entries(.plainText).map(\.text) == ["start", "middle", "end."])
    }

    @Test func plainTextTabComesLastEvenWhenTextLeadsTheLine() {
        let inspection = inspectFixed("hello https://a.test/x")

        #expect(inspection.tabs.map(\.id) == [.pattern("url"), .plainText])
    }

    @Test func noPlainTextTabWhenMatchesCoverEverythingButPunctuation() {
        let inspection = inspectFixed("[https://a.test/x], -- !")

        #expect(inspection.tabs.map(\.id) == [.pattern("url")])
    }

    // MARK: Details

    @Test func jsonEntriesCarryTheParsedValue() throws {
        let json = try #require(monolog.entries(.pattern("json")).first)

        #expect(json.detail == .json(try #require(JSONValue.parse(Fixtures.monologContextJSON))))
    }

    @Test func logLevelAndUserPatternEntriesAreText() {
        var logLevel = Preset.logLevel
        logLevel.enabled = true
        let ticket = Pattern(name: "ticket", regex: #"\bJIRA-\d+\b"#, actions: [.copy])
        let inspection = inspectFixed("ERROR in JIRA-42", config: Config(patterns: [logLevel, ticket]))

        #expect(inspection.entries(.pattern("log level")).first?.detail == .text("ERROR"))
        #expect(inspection.entries(.pattern("ticket")).first?.detail == .text("JIRA-42"))
    }
}

@Suite("Inspection details")
struct InspectionDetailTests {
    func detail(_ input: String, tab: String) -> Detail? {
        inspectFixed(input).entries(.pattern(tab)).first?.detail
    }

    // MARK: URL

    @Test func theMonologURLHasNoQuery() {
        #expect(detail(Fixtures.monologLine, tab: "url") == .url(URLDetail(
            scheme: "http", host: "app.bo.test", path: "/player/api/v1/signin"
        )))
    }

    @Test func queryParametersAreOrderedAndDecodedWithTheFragment() {
        #expect(detail("see https://a.test/x?q=a%20b&id=7#top", tab: "url") == .url(URLDetail(
            scheme: "https", host: "a.test", path: "/x",
            query: [QueryParameter(name: "q", value: "a b"), QueryParameter(name: "id", value: "7")],
            fragment: "top"
        )))
    }

    @Test func repeatedKeysPortAndValuelessParametersAreKept() {
        #expect(detail("https://a.test:8443/p/%C3%A9?tag=a&tag=b&flag&e=x%3Dy", tab: "url") == .url(URLDetail(
            scheme: "https", host: "a.test", port: 8443, path: "/p/é",
            query: [
                QueryParameter(name: "tag", value: "a"), QueryParameter(name: "tag", value: "b"),
                QueryParameter(name: "flag", value: ""), QueryParameter(name: "e", value: "x=y"),
            ]
        )))
    }

    /// Foundation takes a URL with characters it would have to encode, and encodes
    /// its escapes again: they're still decoded once.
    @Test(arguments: [
        ("https://a.test/search?q=caf%C3%A9&t=日本", "/search",
         [QueryParameter(name: "q", value: "café"), QueryParameter(name: "t", value: "日本")], nil as String?),
        ("https://fonts.test/css?family=Open%20Sans|Roboto#x%20y", "/css",
         [QueryParameter(name: "family", value: "Open Sans|Roboto")], "x y"),
        ("https://a.test/caf%C3%A9/日本?flag", "/café/日本", [QueryParameter(name: "flag", value: "")], nil),
    ])
    func aURLWithCharactersToEncodeIsStillDecodedOnce(
        text: String, path: String, query: [QueryParameter], fragment: String?
    ) throws {
        let entry = try #require(inspectFixed(text).entries(.pattern("url")).first)
        #expect(entry.text == text)
        #expect(entry.detail == .url(URLDetail(
            scheme: "https", host: String(text.dropFirst(8).prefix { $0 != "/" }), path: path, query: query,
            fragment: fragment
        )))
    }

    // MARK: File path

    @Test func aBacktracePathHasItsLineAndWhetherItExists() throws {
        let path = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php"
        let input = "at \(path):80 and /tmp/missing.log:12:5"
        let entries = inspectFixed(input, existing: [path]).entries(.pattern("file path"))

        #expect(entries.map(\.detail) == [
            .filePath(FilePathDetail(path: path, line: 80, column: nil, exists: true)),
            .filePath(FilePathDetail(path: "/tmp/missing.log", line: 12, column: 5, exists: false)),
        ])
    }

    @Test func aHomeRelativePathIsExpandedBeforeTheLookup() {
        let entry = inspectFixed("~/notes.md", existing: ["/Users/dev/notes.md"]).entries(.pattern("file path")).first

        #expect(entry?.detail == .filePath(FilePathDetail(path: "/Users/dev/notes.md", line: nil, column: nil, exists: true)))
    }

    @Test func monologBacktraceFramesTakeTheirLinesFromTheLineKey() {
        let entries = inspectFixed(Fixtures.monologLine).entries(.pattern("file path"))

        let files = entries.compactMap { entry -> FilePathDetail? in
            guard case .filePath(let file) = entry.detail else { return nil }
            return file
        }
        #expect(files.count == 6)
        #expect(files.map(\.line) == [nil, 80, 118, 603, 552, 479])
        #expect(files.map(\.lineSource) == [nil, .lineKey, .lineKey, .lineKey, .lineKey, .lineKey])
        #expect(files.map(\.path) == entries.map(\.text))
        #expect(files.allSatisfy { !$0.exists })
    }

    @Test func aPairedEntryPreviewsEndingInItsLineAndKeepsTheLoggedPathAsItsText() throws {
        let entries = inspectFixed(Fixtures.monologLine).entries(.pattern("file path"))

        // A long paired path is cut at the front, so the file name and line stay.
        #expect(entries[1].preview == "…v/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php:80")
        #expect(entries[1].text == "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php")
        #expect(zip(entries.dropFirst(), [".php:80", ".php:118", ".php:603", ".php:552", ".php:479"]).allSatisfy {
            $0.preview.hasSuffix($1)
        })
        #expect(entries.allSatisfy { $0.preview.count <= InspectorEntry.previewLength })
        #expect(!entries[0].preview.contains(":118"))
    }

    @Test func aShortPairedPathPreviewsAsPathColonLine() throws {
        let entry = try #require(inspectFixed(#"{"file":"/app/a.php","line":7}"#).entries(.pattern("file path")).first)

        #expect(entry.preview == "/app/a.php:7")
        #expect(entry.text == "/app/a.php")
        #expect(entry.detail == .filePath(FilePathDetail(path: "/app/a.php", line: 7, column: nil, exists: false, lineSource: .lineKey)))
    }

    @Test func aPathsOwnLineWinsOverTheLineKey() throws {
        let entry = try #require(inspectFixed(#"{"file":"/app/a.php:12","line":7}"#).entries(.pattern("file path")).first)

        #expect(entry.preview == "/app/a.php:12")
        #expect(entry.detail == .filePath(FilePathDetail(path: "/app/a.php", line: 12, column: nil, exists: false, lineSource: .path)))
    }

    @Test func aFilePathOutsideJSONDoesntPair() throws {
        let entry = try #require(inspectFixed(#"file /app/a.php line 7"#).entries(.pattern("file path")).first)

        #expect(entry.detail == .filePath(FilePathDetail(path: "/app/a.php", line: nil, column: nil, exists: false)))
    }

    @Test func pairingWorksInsideAJSONMatchNestedInAnotherMatch() throws {
        var config = Config.default
        config.patterns.append(Pattern(name: "ctx", regex: #"ctx=\{.*\}"#, actions: [.copy]))
        let inspection = inspectFixed(#"at ctx={"file":"/app/a.php","line":"9"} done"#, config: config)

        #expect(inspection.entries(.pattern("json")).first?.parent?.description == "in ctx 0")
        let entry = try #require(inspection.entries(.pattern("file path")).first)
        #expect(entry.preview == "/app/a.php:9")
        guard case .filePath(let file) = entry.detail else { throw CancellationError() }
        #expect(file.line == 9)
        #expect(file.lineSource == .lineKey)
    }

    // MARK: Datetime

    func datetime(_ text: String) throws -> DatetimeDetail {
        guard case .datetime(let detail)? = detail("at \(text) ok", tab: "datetime") else {
            Issue.record("\(text) has no datetime detail")
            throw CancellationError()
        }
        return detail
    }

    @Test func anOffsetlessDatetimeIsAssumedLocal() throws {
        let detail = try datetime("2026-10-07 11:17:10")

        #expect(detail.assumedLocal)
        #expect(detail.conversions == DatetimeConversions(
            instant: Date(timeIntervalSince1970: 1_791_346_630),
            isoUTC: "2026-10-07T04:17:10Z",
            local: "2026-10-07T11:17:10+07:00",
            epochSeconds: "1791346630",
            epochMilliseconds: "1791346630000",
            relative: "2 days ago"
        ))
    }

    @Test func anOffsetlessDatetimeReReadAsUTC() throws {
        let detail = try datetime("2026-10-07 11:17:10")

        #expect(detail.asUTC == DatetimeConversions(
            instant: Date(timeIntervalSince1970: 1_791_371_830),
            isoUTC: "2026-10-07T11:17:10Z",
            local: "2026-10-07T18:17:10+07:00",
            epochSeconds: "1791371830",
            epochMilliseconds: "1791371830000",
            relative: "1 day ago"
        ))
    }

    @Test func aZuluDatetimeWithFractionalSecondsUsesItsOffset() throws {
        let detail = try datetime("2026-10-07T11:17:10.123Z")

        #expect(!detail.assumedLocal)
        #expect(detail.asUTC == nil)
        #expect(detail.conversions.isoUTC == "2026-10-07T11:17:10.123Z")
        #expect(detail.conversions.local == "2026-10-07T18:17:10.123+07:00")
        #expect(detail.conversions.epochSeconds == "1791371830")
        #expect(detail.conversions.epochMilliseconds == "1791371830123")
    }

    @Test(arguments: ["2026-10-07T06:17:10-05:00", "2026-10-07T06:17:10-0500"])
    func anOffsetDatetimeUsesItsOffset(text: String) throws {
        let detail = try datetime(text)

        #expect(!detail.assumedLocal)
        #expect(detail.asUTC == nil)
        #expect(detail.conversions.isoUTC == "2026-10-07T11:17:10Z")
    }

    @Test func longFractionsAreKeptToTheMillisecond() throws {
        #expect(try datetime("2026-10-07T11:17:10.1234567Z").conversions.epochMilliseconds == "1791371830123")
        #expect(try datetime("2026-10-07T11:17:10.5Z").conversions.isoUTC == "2026-10-07T11:17:10.500Z")
    }

    @Test(arguments: ["2026-10-07T04:17:10+0７:0０", "２０２６-10-07", "2026-10-07T0４:17"])
    func digitsOtherThanASCIIAreMatchedButNotRead(text: String) throws {
        // ICU's \d in the Preset takes full-width digits; reading the offset used to trap.
        let entry = try #require(inspectFixed("at \(text) ok").entries(.pattern("datetime")).first)
        #expect(entry.text == text)
        #expect(entry.detail == .text(text))
    }

    @Test func aDateAloneIsLocalMidnight() throws {
        let detail = try datetime("2026-10-07")

        #expect(detail.assumedLocal)
        #expect(detail.conversions.local == "2026-10-07T00:00:00+07:00")
        #expect(detail.asUTC?.isoUTC == "2026-10-07T00:00:00Z")
    }

    @Test func aTenDigitEpochIsSecondsInUTC() throws {
        let detail = try datetime("1759835830")

        #expect(!detail.assumedLocal)
        #expect(detail.asUTC == nil)
        #expect(detail.conversions.isoUTC == "2025-10-07T11:17:10Z")
        #expect(detail.conversions.local == "2025-10-07T18:17:10+07:00")
        #expect(detail.conversions.epochSeconds == "1759835830")
        #expect(detail.conversions.epochMilliseconds == "1759835830000")
        #expect(detail.conversions.relative == "1 year ago")
    }

    @Test func aThirteenDigitEpochIsMillisecondsInUTC() throws {
        let detail = try datetime("1759835830123")

        #expect(!detail.assumedLocal)
        #expect(detail.conversions.isoUTC == "2025-10-07T11:17:10.123Z")
        #expect(detail.conversions.epochSeconds == "1759835830")
        #expect(detail.conversions.epochMilliseconds == "1759835830123")
    }

    @Test(arguments: [
        ("2026-10-09T04:59:31Z", "just now"),
        ("2026-10-09T04:59:00Z", "1 minute ago"),
        ("2026-10-09T04:55:00Z", "5 minutes ago"),
        ("2026-10-09T02:00:00Z", "3 hours ago"),
        ("2026-10-09T08:00:00Z", "in 3 hours"),
        ("2026-10-12T05:00:00Z", "in 3 days"),
        ("2026-08-01T05:00:00Z", "2 months ago"),
        ("2024-10-01T05:00:00Z", "2 years ago"),
    ])
    func relativeTimeIsCountedFromNow(text: String, relative: String) throws {
        #expect(try datetime(text).conversions.relative == relative)
    }
}

@Suite("Inspection while editing")
struct InspectionEditingTests {
    let monolog = inspectFixed(Fixtures.monologLine)

    @Test func aNewPatternBeforeTheOthersAppendsItsTabBeforePlainText() {
        let input = "x.log /var/log/x.log 2026-10-07 11:17:10 https://a.test/x"
        let first = inspectFixed("2026-10-07 11:17:10 https://a.test/x")
        let edited = inspectFixed(input, previous: first)

        #expect(first.tabs.map(\.id) == [.pattern("datetime"), .pattern("url")])
        #expect(edited.tabs.map(\.id) == [.pattern("datetime"), .pattern("url"), .pattern("file path"), .plainText])
        // Fresh, the same Input orders tabs by first appearance.
        #expect(inspectFixed(input).tabs.map(\.id) == [
            .pattern("file path"), .pattern("datetime"), .pattern("url"), .plainText,
        ])
    }

    @Test func typingAURLBeforeTheDatetimeKeepsTheOrder() {
        let edited = inspectFixed("https://a.test/x " + Fixtures.monologLine, previous: monolog)

        #expect(edited.tabs.map(\.id) == [
            .pattern("datetime"), .pattern("json"), .pattern("url"), .pattern("file path"), .plainText,
        ])
        #expect(edited.entries(.pattern("url")).count == 2)
    }

    @Test func deletingTheOnlyDatetimeDropsItsTabAndFallsBackToTheLargestMatch() {
        var previous = monolog
        previous.selection = EntryID(tab: .pattern("datetime"), index: 0)
        let edited = inspectFixed(Fixtures.monologLine.replacingOccurrences(of: "2026-10-07 11:17:10", with: "now"), previous: previous)

        #expect(edited.tabs.map(\.id) == [.pattern("json"), .pattern("url"), .pattern("file path"), .plainText])
        #expect(edited.selection == EntryID(tab: .pattern("json"), index: 0))
    }

    @Test func editingInsideTheSelectedFilePathKeepsAFilePathSelected() {
        var previous = monolog
        previous.selection = EntryID(tab: .pattern("file path"), index: 4)
        let line = Fixtures.monologLine.replacingOccurrences(of: "Dispatcher.php\",\"line\":552", with: "Dispatch.php\",\"line\":552")
        let edited = inspectFixed(line, previous: previous)

        #expect(edited.selection == EntryID(tab: .pattern("file path"), index: 4))
        #expect(edited.selectedEntry?.text.hasSuffix("Events/Dispatch.php") == true)
    }

    @Test func deletingTheSelectedMatchMovesToTheNearestOfTheSamePattern() {
        var previous = inspectFixed("https://a.test/1 https://b.test/2 2026-10-07 https://c.test/3")
        previous.selection = EntryID(tab: .pattern("url"), index: 1)
        let edited = inspectFixed("https://a.test/1 2026-10-07 https://c.test/3", previous: previous)

        #expect(edited.selectedEntry?.text == "https://c.test/3")
    }

    @Test func typingInsideTheSelectedMatchKeepsIt() {
        var previous = inspectFixed("https://a.test/1 https://b.test/2 https://c.test/3")
        previous.selection = EntryID(tab: .pattern("url"), index: 1)
        let edited = inspectFixed("https://a.test/1 https://b.test/2345 https://c.test/3", previous: previous)

        #expect(edited.selection == EntryID(tab: .pattern("url"), index: 1))
    }

    @Test func theSelectionFollowsATextShiftWhenOverlappingIsAmbiguous() {
        var previous = inspectFixed("https://a.test/1 https://b.test/2")
        previous.selection = EntryID(tab: .pattern("url"), index: 1)
        let edited = inspectFixed("xyz https://a.test/1 https://b.test/2", previous: previous)

        #expect(edited.selectedEntry?.text == "https://b.test/2")
    }

    @Test func aPlainTextSelectionStaysInPlainText() {
        var previous = monolog
        previous.selection = EntryID(tab: .plainText, index: 0)
        let edited = inspectFixed(Fixtures.monologLine.replacingOccurrences(of: "invoked", with: "called"), previous: previous)

        #expect(edited.selection == EntryID(tab: .plainText, index: 0))
        #expect(edited.selectedEntry?.text.contains("__call called") == true)
    }

    @Test func noPreviousSelectionFallsBackToTheLargestMatch() {
        var previous = monolog
        previous.selection = nil

        #expect(inspectFixed(Fixtures.monologLine, previous: previous).selection == EntryID(tab: .pattern("json"), index: 0))
    }

    @Test func disablingAPatternDropsItsTab() {
        var config = Config.default
        config.patterns.removeAll { $0.name == "url" }

        #expect(inspectFixed(Fixtures.monologLine, config: config, previous: monolog).tabs.map(\.id) == [
            .pattern("datetime"), .pattern("json"), .pattern("file path"), .plainText,
        ])
    }

    @Test func aSelectionMadeSinceTheInspectionStartedIsKeptLikeAnEditsPrevious() {
        let input = "https://a.test/1 https://b.test/2 https://c.test/3"
        let started = inspectFixed(input)
        // Started from the first URL selected; the user picked the third meanwhile.
        let next = inspectFixed(input, previous: started)
        var current = started
        current.selection = EntryID(tab: .pattern("url"), index: 2)

        #expect(next.selection == EntryID(tab: .pattern("url"), index: 0))
        #expect(next.selection(keeping: current) == EntryID(tab: .pattern("url"), index: 2))
        #expect(next.selection(keeping: nil) == EntryID(tab: .pattern("url"), index: 0))
    }
}
