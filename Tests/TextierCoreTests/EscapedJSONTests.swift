import Foundation
import Testing
import TextierCore

@Suite("Escaped JSON")
struct EscapedJSONTests {
    /// JSON logged as a string value inside JSON.
    let escaped = JSONValue.parse(#"{"payload":"{\"a\":1,\"b\":[1,2]}"}"#)!
    /// Escaped JSON inside escaped JSON: each level escapes the one below it once more.
    let doubleEscaped = JSONValue.parse(#"{"outer":"{\"inner\":\"{\\\"x\\\":1}\",\"n\":2}"}"#)!

    // MARK: Detection and unescaping

    @Test func aStringHoldingAnObjectYieldsThatObjectInOrder() throws {
        let parsed = try #require(escaped["payload"]?.escapedJSON)

        #expect(parsed == .object([
            JSONEntry(key: "a", value: .number("1")),
            JSONEntry(key: "b", value: .array([.number("1"), .number("2")])),
        ]))
    }

    @Test func aStringHoldingAnArrayIsEscapedJSON() {
        #expect(JSONValue.string(#"[{"id":7}, "x"]"#).escapedJSON == .array([
            .object([JSONEntry(key: "id", value: .number("7"))]), .string("x"),
        ]))
    }

    @Test func surroundingWhitespaceInsideTheStringIsAllowed() {
        #expect(JSONValue.string("\n  {\"a\": true}\n").escapedJSON == .object([JSONEntry(key: "a", value: .bool(true))]))
    }

    @Test func escapedJSONTwoLevelsDeepUnescapesAtBothLevels() throws {
        let outer = try #require(doubleEscaped["outer"]?.escapedJSON)
        let inner = try #require(outer["inner"]?.escapedJSON)

        #expect(outer["n"] == .number("2"))
        #expect(inner == .object([JSONEntry(key: "x", value: .number("1"))]))
    }

    @Test(arguments: [
        "{not json}",
        "use {name} here",
        "{\"a\":1} trailing",
        "[1, 2",
        "Illuminate\\Events\\{closure}",
        "",
    ])
    func stringsThatMerelyContainBracesAreNotEscapedJSON(string: String) {
        #expect(JSONValue.string(string).escapedJSON == nil)
    }

    @Test(arguments: ["1", "\"x\"", "true", "null"])
    func stringsHoldingAScalarAreNotEscapedJSON(string: String) {
        #expect(JSONValue.string(string).escapedJSON == nil)
    }

    @Test(arguments: ["{}", "[]", " [ ] "])
    func stringsHoldingAnEmptyContainerAreNotEscapedJSON(string: String) {
        #expect(JSONValue.string(string).escapedJSON == nil)
    }

    @Test func onlyStringValuesCanBeEscapedJSON() {
        #expect(escaped.escapedJSON == nil)
        #expect(JSONValue.number("1").escapedJSON == nil)
    }

    @Test func childKeyPathsRunThroughTheStringsKey() {
        #expect(keyPath([.key("context"), .key("payload"), .key("b"), .index(1)]) == "context.payload.b[1]")
    }

    // MARK: The Built-in Pattern

    @Test func theBuiltinOffersOpen() {
        #expect(Builtin.escapedJSON.name == "escaped-json")
        #expect(Builtin.escapedJSON.kind == .builtin(.escapedJSON))
        #expect(Builtin.escapedJSON.actions == [.open])
        #expect(Builtin.escapedJSON.enabled)
    }

    @Test func theDefaultConfigEnablesItRightAfterJSON() {
        #expect(Config.default.patterns.prefix(2) == [Builtin.json, Builtin.escapedJSON])
        #expect(Config.default.escapedJSONPattern == Builtin.escapedJSON)
    }

    @Test func disablingOrOmittingItTurnsEscapedJSONOff() {
        var disabled = Builtin.escapedJSON
        disabled.enabled = false

        #expect(Config(patterns: [Builtin.json, disabled]).escapedJSONPattern == nil)
        #expect(Config(patterns: [Builtin.json]).escapedJSONPattern == nil)
    }

    @Test func itNeverMatchesTheInputItself() {
        let input = #"[2026-10-07 11:17:10] local.INFO: {"payload":"{\"a\":1}"}"#

        #expect(detect(input, config: Config(patterns: [Builtin.escapedJSON])).isEmpty)
    }

    // MARK: The config file

    @Test func theFirstLaunchFileHasTheEntryEnabledAndLoadsItBack() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))

        let entry = [#""name": "escaped-json""#, #""builtin": "escaped-json""#, #""enabled": true"#, #""actions": ["open"]"#]
        #expect(text.contains(entry.map { "      " + $0 }.joined(separator: ",\n")))
        #expect(ConfigFile.load(ConfigFile.encode(.default)).config?.escapedJSONPattern == Builtin.escapedJSON)
    }

    @Test func aFileDisablingItLoadsWithItOff() throws {
        let file = #"""
        { "patterns": [
          { "name": "json", "builtin": "json", "actions": ["open"] },
          { "name": "escaped-json", "builtin": "escaped-json", "enabled": false, "actions": ["open"] }
        ] }
        """#
        let config = try #require(ConfigFile.load(Data(file.utf8)).config)

        #expect(config.patterns.count == 2)
        #expect(config.escapedJSONPattern == nil)
    }
}
