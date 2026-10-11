import Testing
import TextierCore

@Suite("JSON Viewer tree seams")
struct JSONTreeTests {
    let context = JSONValue.parse(Fixtures.monologContextJSON)!

    // MARK: Key paths

    @Test func firstBacktraceFrameFileHasTheDottedBracketedKeyPath() {
        #expect(keyPath([.key("backtrace"), .index(0), .key("file")]) == "backtrace[0].file")
    }

    @Test(arguments: [
        ([JSONPathComponent](), ""),
        ([.key("url")], "url"),
        ([.index(3)], "[3]"),
        ([.index(0), .key("id")], "[0].id"),
        ([.key("a"), .key("b"), .key("c")], "a.b.c"),
        ([.key("rows"), .index(1), .index(2)], "rows[1][2]"),
        ([.key("_private$1")], "_private$1"),
        ([.key("$ref")], "$ref"),
    ])
    func identifierKeysAndIndices(components: [JSONPathComponent], expected: String) {
        #expect(keyPath(components) == expected)
    }

    @Test(arguments: [
        ([JSONPathComponent.key("content-type")], #"["content-type"]"#),
        ([.key("headers"), .key("content-type")], #"headers["content-type"]"#),
        ([.key("1st")], #"["1st"]"#),
        ([.key("")], #"[""]"#),
        ([.key("has space"), .key("ok")], #"["has space"].ok"#),
        ([.key(#"say "hi""#)], #"["say \"hi\""]"#),
        ([.key(#"back\slash"#)], #"["back\\slash"]"#),
        ([.key("é")], #"["é"]"#),
    ])
    func nonIdentifierKeysAreBracketQuoted(components: [JSONPathComponent], expected: String) {
        #expect(keyPath(components) == expected)
    }

    // MARK: Initial expansion

    @Test func monologBacktraceAndItsFramesAreExpandedOnOpen() throws {
        let backtrace = try #require(context["backtrace"])
        guard case .array(let frames) = backtrace else { Issue.record("not an array"); return }

        #expect(frames.count == 5)
        #expect(context.isExpandedOnOpen(atDepth: 0))
        #expect(backtrace.isExpandedOnOpen(atDepth: 1))
        #expect(frames.allSatisfy { $0.isExpandedOnOpen(atDepth: 2) })
    }

    @Test func containersBelowDepthTwoAreCollapsedOnOpen() {
        let deep = JSONValue.parse(#"{"a":{"b":{"c":{"d":1}}}}"#)!

        #expect(deep.isExpandedOnOpen(atDepth: 2))
        #expect(!deep.isExpandedOnOpen(atDepth: 3))
    }

    @Test func arraysLongerThanTwentyItemsAreCollapsedAtAnyDepth() {
        let long = JSONValue.parse("[" + (1...25).map(String.init).joined(separator: ",") + "]")!
        let twenty = JSONValue.parse("[" + (1...20).map(String.init).joined(separator: ",") + "]")!

        #expect(!long.isExpandedOnOpen(atDepth: 1))
        #expect(!long.isExpandedOnOpen(atDepth: 0))
        #expect(twenty.isExpandedOnOpen(atDepth: 1))
    }

    @Test func largeObjectsAreNotCollapsedByTheArrayRule() {
        let wide = JSONValue.parse("{" + (1...25).map { #""k\#($0)":\#($0)"# }.joined(separator: ",") + "}")!

        #expect(wide.isExpandedOnOpen(atDepth: 1))
    }

    @Test func scalarsAreNeverExpanded() {
        #expect(!JSONValue.string("x").isExpandedOnOpen(atDepth: 0))
        #expect(!JSONValue.number("1").isExpandedOnOpen(atDepth: 1))
    }

    // MARK: Copy value

    @Test func copyValueOnTheFirstFrameIsThatFrameAsPrettyJSON() throws {
        guard case .array(let frames)? = context["backtrace"] else { Issue.record("no backtrace"); return }

        #expect(frames[0].copyText == """
            {
              "file": "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php",
              "line": 80,
              "function": "__call"
            }
            """)
    }

    @Test(arguments: [
        (JSONValue.string(#"Modules\Notification"#), #"Modules\Notification"#),
        (.string("http://app.bo.test/player/api/v1/signin"), "http://app.bo.test/player/api/v1/signin"),
        (.number("118"), "118"),
        (.number("1.50"), "1.50"),
        (.bool(true), "true"),
        (.bool(false), "false"),
        (.null, "null"),
    ])
    func copyValueOnAScalarIsItsRawValue(value: JSONValue, expected: String) {
        #expect(value.copyText == expected)
    }

    // MARK: String values that are Matches

    @Test func aURLStringValueIsAMatchWithOpenURLFirst() throws {
        let match = try #require(stringValueMatch("http://app.bo.test/player/api/v1/signin", config: .default))

        #expect(match.patternName == "url")
        #expect(match.actions.first == .openURL)
    }

    @Test func aBacktraceFileStringValueIsAMatchWithOpenFileFirst() throws {
        let file = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php"
        let match = try #require(stringValueMatch(file, config: .default))

        #expect(match.patternName == "file path")
        #expect(match.actions.first == .openFile)
    }

    @Test(arguments: [
        "findActiveTemplate",
        "see http://a.test/x for details",
        #"Modules\Notification\Repositories\EmailTemplateRepository"#,
        "",
    ])
    func stringsThatAreNotWhollyOneMatchCarryNoActions(string: String) {
        #expect(stringValueMatch(string, config: .default) == nil)
    }

    @Test func builtinPatternsDoNotApplyToStringValues() {
        // Escaped JSON inside a string value is the escaped-json Pattern's job (ticket 08).
        #expect(stringValueMatch(#"{"a":1}"#, config: .default) == nil)
    }

    @Test(arguments: ["2026-10-07 11:17:10", "1728299830", "WARNING"])
    func stringsMatchedOnlyByPatternsWithoutOpenActionsCarryNoActions(string: String) {
        var logLevel = Preset.logLevel
        logLevel.enabled = true
        let config = Config(patterns: Config.default.patterns + [logLevel])

        #expect(stringValueMatch(string, config: config) == nil)
    }

    @Test func aUserPatternDeclaringOpenURLStillCarriesItsActions() throws {
        let ticket = Pattern(name: "ticket url", regex: #"JIRA-\d+"#, actions: [.copy, .openURL])
        let match = try #require(stringValueMatch("JIRA-123", config: Config(patterns: [ticket])))

        #expect(match.patternName == "ticket url")
        #expect(match.actions == [.copy, .openURL])
    }

    @Test func disabledPatternsDoNotApplyToStringValues() {
        var url = Preset.url
        url.enabled = false

        #expect(stringValueMatch("http://a.test/x", config: Config(patterns: [url])) == nil)
    }
}
