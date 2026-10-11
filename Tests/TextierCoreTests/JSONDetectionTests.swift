import Foundation
import Testing
import TextierCore

@Suite("JSON Built-in detection")
struct JSONDetectionTests {
    let jsonOnly = Config(patterns: [Builtin.json])

    @Test func monologContextPayloadIsOneJSONMatchWithItsSourceText() throws {
        let matches = detect(Fixtures.monologLine, config: jsonOnly)

        #expect(matches.map(\.text) == [Fixtures.monologContextJSON])
        let match = try #require(matches.first)
        #expect(match.patternName == "json")
        #expect(match.actions == [.open, .copyPretty, .copy])
        #expect((Fixtures.monologLine as NSString).substring(with: match.range) == match.text)
    }

    @Test func monologLineInTheDefaultConfigIsDatetimeThenJSONWithURLAndPathsAsChildren() throws {
        let matches = detect(Fixtures.monologLine, config: .default)

        #expect(matches.map(\.patternName) == ["datetime", "json"])
        let json = try #require(matches.last)
        #expect(json.children.map(\.patternName) == ["url"] + Array(repeating: "file path", count: 6))
        #expect(json.children.first?.text == "http://app.bo.test/player/api/v1/signin")
    }

    @Test func bracketedLogPrefixesThatAreNotJSONAreSkipped() {
        let input = "[2026-10-07 11:17:10] develop.WARNING: [REPOSITORY SCOPE LEAK] done"

        #expect(detect(input, config: jsonOnly).isEmpty)
    }

    @Test func aTopLevelArrayIsDetectedMidLine() {
        let input = #"ids=[1, 2, {"k": "v"}] end"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"[1, 2, {"k": "v"}]"#])
    }

    @Test func invalidJSONLookingTextIsNotAMatch() {
        #expect(detect("payload {not json} here", config: jsonOnly).isEmpty)
    }

    @Test func aValidObjectInsideAnInvalidOneIsStillFound() {
        let input = #"{broken {"ok":true} still broken"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"{"ok":true}"#])
    }

    @Test func jsonSpanningSeveralLinesIsOneMatch() {
        let input = """
        response:
        {
          "status": 200,
          "body": [
            "a",
            "b"
          ]
        }
        done
        """

        let matches = detect(input, config: jsonOnly)
        #expect(matches.count == 1)
        #expect(matches.first?.text.hasPrefix("{\n  \"status\"") == true)
        #expect(matches.first?.text.hasSuffix("]\n}") == true)
    }

    @Test func scanningResumesAfterAMatchSoNestedValuesAreNotSeparateTopLevelMatches() {
        let input = #"a {"x":{"y":[1]}} b [2] c"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"{"x":{"y":[1]}}"#, "[2]"])
    }

    @Test func rangesAreUTF16() throws {
        let input = #"😀 é {"a":"ü"}"#

        let match = try #require(detect(input, config: jsonOnly).first)
        #expect((input as NSString).substring(with: match.range) == #"{"a":"ü"}"#)
    }

    @Test func disabledJSONProducesNoMatches() {
        var json = Builtin.json
        json.enabled = false

        #expect(detect(Fixtures.monologLine, config: Config(patterns: [json])).isEmpty)
    }

    @Test(arguments: [
        "items[0] = 1",
        "$row['id'] and $row[\"id\"]",
        "matrix[1][2]",
        "call()[0]",
        "frames[ 3 ]",
    ])
    func indexSyntaxRightAfterAnIdentifierIsNotJSON(input: String) {
        #expect(detect(input, config: jsonOnly).isEmpty)
    }

    @Test func jsonInsideAnIndexExpressionIsStillFound() {
        let input = #"lookup[{"id":7}]"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"{"id":7}"#])
    }

    @Test func emptyObjectsAndArraysAreNotMatches() {
        let input = "context {} extra [] spaced { } and [ ]"

        #expect(detect(input, config: jsonOnly).isEmpty)
    }

    @Test func monologLinesWithEmptyContextAndExtraKeepOnlyRealPayloads() {
        let input = #"[2026-10-07 11:17:10] local.INFO: done {"user":1} []"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"{"user":1}"#])
    }

    @Test func manyUnclosedBracketsDoNotCrashTheScanner() {
        let input = String(repeating: "{[", count: 5_000) + #" {"ok":1}"#

        #expect(detect(input, config: jsonOnly).map(\.text) == [#"{"ok":1}"#])
    }
}
