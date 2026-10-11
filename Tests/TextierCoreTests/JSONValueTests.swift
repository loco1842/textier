import Testing
import TextierCore

@Suite("JSON parsing and pretty-printing")
struct JSONValueTests {
    @Test func parsesScalarsAndContainersIntoTheOrderedModel() {
        let value = JSONValue.parse(#"{"b":1,"a":[true,false,null,"x",-2.5e3]}"#)

        #expect(value == .object([
            JSONEntry(key: "b", value: .number("1")),
            JSONEntry(key: "a", value: .array([.bool(true), .bool(false), .null, .string("x"), .number("-2.5e3")])),
        ]))
    }

    @Test func objectKeysKeepTheirSourceOrder() throws {
        let value = try #require(JSONValue.parse(#"{"zeta":1,"alpha":2,"mid":3}"#))

        guard case .object(let entries) = value else { Issue.record("not an object"); return }
        #expect(entries.map(\.key) == ["zeta", "alpha", "mid"])
    }

    @Test func duplicateKeysAreKeptInOrder() throws {
        let value = try #require(JSONValue.parse(#"{"a":1,"a":2}"#))

        #expect(value == .object([JSONEntry(key: "a", value: .number("1")), JSONEntry(key: "a", value: .number("2"))]))
    }

    @Test func prettyPrintsWithTwoSpaceIndentAndSourceKeyOrder() throws {
        let value = try #require(JSONValue.parse(#"{"url":"http://a.test","n":1,"list":[1,{"k":null}],"empty":{},"none":[]}"#))

        #expect(value.prettyPrinted == """
        {
          "url": "http://a.test",
          "n": 1,
          "list": [
            1,
            {
              "k": null
            }
          ],
          "empty": {},
          "none": []
        }
        """)
    }

    @Test func prettyPrintingHasNoTrailingWhitespace() throws {
        let value = try #require(JSONValue.parse(Fixtures.monologContextJSON))

        let lines = value.prettyPrinted.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.allSatisfy { $0.last != " " })
        #expect(value.prettyPrinted.last == "}")
    }

    @Test func monologContextJSONRoundTripsThroughPrettyPrintAndBack() throws {
        let value = try #require(JSONValue.parse(Fixtures.monologContextJSON))

        #expect(JSONValue.parse(value.prettyPrinted) == value)
    }

    @Test func monologContextJSONPrettyPrintStartsWithItsKeysInLoggedOrder() throws {
        let value = try #require(JSONValue.parse(Fixtures.monologContextJSON))

        let firstLines = value.prettyPrinted.split(separator: "\n").prefix(8).map(String.init)
        #expect(firstLines == [
            "{",
            #"  "url": "http://app.bo.test/player/api/v1/signin","#,
            #"  "repository": "Modules\\Notification\\Repositories\\EmailTemplateRepository","#,
            #"  "method": "where","#,
            #"  "scope_count": 1,"#,
            #"  "caller_file": "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php","#,
            #"  "caller_line": 118,"#,
            #"  "caller_function": "findActiveTemplate","#,
        ])
    }

    @Test func stringEscapesAreDecoded() {
        #expect(JSONValue.parse(#"["a\"b\\c\/d\n\t\r\b\f"]"#) == .array([.string("a\"b\\c/d\n\t\r\u{8}\u{c}")]))
        #expect(JSONValue.parse(#"["é中"]"#) == .array([.string("é中")]))
        #expect(JSONValue.parse(#"["😀"]"#) == .array([.string("😀")]))
    }

    @Test func prettyPrintingNormalisesStringEscapes() throws {
        let value = try #require(JSONValue.parse(#"["\/path","é","\u0001","tab\there","q\"uote\\"]"#))

        #expect(value.prettyPrinted == #"""
        [
          "/path",
          "é",
          "\u0001",
          "tab\there",
          "q\"uote\\"
        ]
        """#)
    }

    @Test func numbersKeepTheirSourceText() throws {
        let value = try #require(JSONValue.parse("[1.50,-0,1E+2,12345678901234567890]"))

        #expect(value.prettyPrinted == "[\n  1.50,\n  -0,\n  1E+2,\n  12345678901234567890\n]")
    }

    @Test func surroundingWhitespaceIsAllowedButTrailingTextIsNot() {
        #expect(JSONValue.parse("  {\"a\": 1}\n") != nil)
        #expect(JSONValue.parse(#"{"a":1} x"#) == nil)
    }

    @Test(arguments: [
        "{not json}",
        "{",
        "[1,]",
        #"{"a":1,}"#,
        #"{'a':1}"#,
        "[01]",
        "[1.]",
        "[.5]",
        "[+1]",
        "[NaN]",
        "[tru]",
        "[\"unterminated]",
        "[\"raw\nnewline\"]",
        #"["\x"]"#,
        #"["\u12"]"#,
        #"{"a" 1}"#,
        "",
    ])
    func rejectsInvalidJSON(text: String) {
        #expect(JSONValue.parse(text) == nil)
    }

    @Test func deeplyNestedInputFailsInsteadOfCrashing() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)

        #expect(JSONValue.parse(deep) == nil)
    }

    @Test func moderatelyNestedInputParses() {
        let nested = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)

        #expect(JSONValue.parse(nested) != nil)
    }

    @Test func scanParsesOneValueFromAUTF16OffsetAndReportsItsLength() throws {
        let text = #"é {"a":[1,2]} tail"#

        let scanned = try #require(JSONValue.scan(text, at: 2))
        #expect(scanned.length == 11)
        #expect(scanned.value == .object([JSONEntry(key: "a", value: .array([.number("1"), .number("2")]))]))
        #expect(JSONValue.scan(text, at: 0) == nil)
    }

    @Test func containerFromTextIsTheParsedObjectOrArrayOnly() throws {
        #expect(JSONValue.container(from: Fixtures.monologContextJSON) == JSONValue.parse(Fixtures.monologContextJSON))
        #expect(JSONValue.container(from: "[1, 2]") == .array([.number("1"), .number("2")]))
        #expect(JSONValue.container(from: "[]") == .array([]))
        for scalar in [#""text""#, "42", "true", "null", "{not json}", "/Users/mac/file.php:118"] {
            #expect(JSONValue.container(from: scalar) == nil)
        }
    }

    @Test func onlyObjectsAndArraysWithSomethingInThemAreNonEmptyContainers() {
        #expect(JSONValue.parse(#"{"a":1}"#)?.isNonEmptyContainer == true)
        #expect(JSONValue.parse("[0]")?.isNonEmptyContainer == true)
        #expect(JSONValue.parse("{ }")?.isNonEmptyContainer == false)
        #expect(JSONValue.parse("[]")?.isNonEmptyContainer == false)
        #expect(JSONValue.parse("[]")?.isContainer == true)
        #expect(JSONValue.string("{}").isNonEmptyContainer == false)
    }
}
