import Testing
import TextierCore

@Suite("JSONPath queries (RFC 9535)")
struct JSONPathTests {
    let context = JSONValue.parse(Fixtures.monologContextJSON)!

    /// The key paths `query` finds in the Monolog context, as the path bar writes them.
    func paths(_ query: String, in value: JSONValue? = nil) throws -> [String] {
        try JSONPathQuery(query).evaluate(value ?? context).map { keyPath($0.path) }
    }

    // MARK: Segments

    @Test func theRootIsItself() throws {
        #expect(try paths("$") == [""])
    }

    @Test func namesStepIntoObjects() throws {
        #expect(try paths("$.method") == ["method"])
        #expect(try paths("$['method']") == ["method"])
        #expect(try paths(#"$["caller_line"]"#) == ["caller_line"])
        #expect(try paths("$.nope").isEmpty)
    }

    @Test func indicesStepIntoArraysFromEitherEnd() throws {
        #expect(try paths("$.backtrace[0].file") == ["backtrace[0].file"])
        #expect(try paths("$.backtrace[-1].line") == ["backtrace[4].line"])
        #expect(try paths("$.backtrace[9]").isEmpty)
    }

    @Test func wildcardsTakeEveryMemberOrElement() throws {
        #expect(try paths("$.backtrace[*].line") == (0..<5).map { "backtrace[\($0)].line" })
        #expect(try paths("$.backtrace[0].*") == ["backtrace[0].file", "backtrace[0].line", "backtrace[0].function"])
    }

    @Test func slicesTakeARange() throws {
        #expect(try paths("$.backtrace[1:3]") == ["backtrace[1]", "backtrace[2]"])
        #expect(try paths("$.backtrace[:2]") == ["backtrace[0]", "backtrace[1]"])
        #expect(try paths("$.backtrace[-2:]") == ["backtrace[3]", "backtrace[4]"])
        #expect(try paths("$.backtrace[::2]") == ["backtrace[0]", "backtrace[2]", "backtrace[4]"])
        #expect(try paths("$.backtrace[::-2]") == ["backtrace[4]", "backtrace[2]", "backtrace[0]"])
    }

    @Test func severalSelectorsInOneBracket() throws {
        #expect(try paths("$['url','method']") == ["url", "method"])
        #expect(try paths("$.backtrace[0,-1].line") == ["backtrace[0].line", "backtrace[4].line"])
    }

    @Test func descendantsFindAKeyAtAnyDepthInDocumentOrder() throws {
        #expect(try paths("$..line") == (0..<5).map { "backtrace[\($0)].line" })
        #expect(try paths("$..[0].function") == ["backtrace[0].function"])
        let nested = JSONValue.parse(#"{"a": {"a": 1}, "b": [{"a": 2}]}"#)!
        #expect(try paths("$..a", in: nested) == ["a", "a.a", "b[0].a"])
    }

    // MARK: Filters

    @Test func filtersCompareNumbersAndStrings() throws {
        #expect(try paths("$.backtrace[?@.line > 500]") == ["backtrace[2]", "backtrace[3]"])
        #expect(try paths("$.backtrace[?@.line <= 80]") == ["backtrace[0]"])
        #expect(try paths("$.backtrace[?@.function == '__call'].file") == ["backtrace[0].file"])
        #expect(try paths("$.backtrace[?@.function != '__call']").count == 4)
        #expect(try paths("$.backtrace[?@.line == 118]") == ["backtrace[1]"])
    }

    @Test func filtersCombineWithAndOrNot() throws {
        #expect(try paths("$.backtrace[?@.line > 100 && @.line < 600]") == ["backtrace[1]", "backtrace[3]", "backtrace[4]"])
        #expect(try paths("$.backtrace[?@.line == 80 || @.line == 479]") == ["backtrace[0]", "backtrace[4]"])
        #expect(try paths("$.backtrace[?!(@.line > 100)]") == ["backtrace[0]"])
    }

    @Test func aFilterQueryAloneTestsThatSomethingIsThere() throws {
        let items = JSONValue.parse(#"[{"a": 1}, {"b": 2}, {"a": null}]"#)!
        #expect(try paths("$[?@.a]", in: items) == ["[0]", "[2]"])
        #expect(try paths("$[?!@.a]", in: items) == ["[1]"])
    }

    @Test func filtersCanReachTheRoot() throws {
        #expect(try paths("$.backtrace[?@.line == $.caller_line].function") == ["backtrace[1].function"])
    }

    @Test func differentTypesAreNeverEqualAndOnlyOrderLikeWithLike() throws {
        let items = JSONValue.parse(#"[{"v": 1}, {"v": "1"}, {"v": true}, {"v": null}]"#)!
        #expect(try paths("$[?@.v == 1]", in: items) == ["[0]"])
        #expect(try paths("$[?@.v == '1']", in: items) == ["[1]"])
        #expect(try paths("$[?@.v == true]", in: items) == ["[2]"])
        #expect(try paths("$[?@.v == null]", in: items) == ["[3]"])
        #expect(try paths("$[?@.v > 0]", in: items) == ["[0]"])
        #expect(try paths("$[?@.missing == @.other]", in: items).count == 4)
    }

    @Test func functionsMatchSearchLengthAndCount() throws {
        #expect(try paths("$.backtrace[?search(@.file, 'vendor')].line") == ["backtrace[2].line", "backtrace[3].line", "backtrace[4].line"])
        #expect(try paths("$.backtrace[?match(@.function, 'find.*')]") == ["backtrace[1]"])
        #expect(try paths("$.backtrace[?match(@.function, 'find')]").isEmpty)
        #expect(try paths("$.backtrace[?length(@.function) > 12]") == ["backtrace[1]", "backtrace[3]", "backtrace[4]"])
        #expect(try paths("$[?count(@.*) == 3]", in: .array([context])).isEmpty)
        #expect(try paths("$.backtrace[?count(@.*) == 3]").count == 5)
    }

    @Test func matchTakesTheWholeStringNotUpToATrailingNewline() throws {
        let items = JSONValue.parse(#"["Done\n", "Done"]"#)!
        #expect(try paths("$[?match(@, 'Done')]", in: items) == ["[1]"])
    }

    @Test func aRegexEscapeIsWrittenWithTwoBackslashes() throws {
        let items = JSONValue.parse(#"["abc", "a12", "x.php", "xphp"]"#)!
        #expect(try paths(#"$[?search(@, '\\d+')]"#, in: items) == ["[1]"])
        #expect(try paths(#"$[?search(@, '\\.php$')]"#, in: items) == ["[2]"])
    }

    @Test func numbersCompareExactlyBeyondADoublesDigits() throws {
        let ids = JSONValue.parse("[1180591793285107713, 1180591793285107714, 1180591793285107800]")!
        #expect(try paths("$[?@ == 1180591793285107713]", in: ids) == ["[0]"])
        #expect(try paths("$[?@ > 1180591793285107713]", in: ids) == ["[1]", "[2]"])
        #expect(try paths("$[?@ <= 1180591793285107714]", in: ids) == ["[0]", "[1]"])
        let numbers = JSONValue.parse("[1.0, 100, 2.5]")!
        #expect(try paths("$[?@ == 1]", in: numbers) == ["[0]"])
        #expect(try paths("$[?@ == 1e2]", in: numbers) == ["[1]"])
        #expect(try paths("$[?@ < 2.50]", in: numbers) == ["[0]"])
        #expect(try paths("$[?@ >= 2.50]", in: numbers) == ["[1]", "[2]"])
    }

    // MARK: Results and errors

    @Test func aKeyTwiceGivesEachEntryItsOwnOrdinal() throws {
        let object = JSONValue.parse(#"{"a": 1, "a": 2}"#)!
        let all = try JSONPathQuery("$.*").evaluate(object)
        #expect(all.map(\.ordinals) == [[0], [1]])
        #expect(all.map(\.value) == [.number("1"), .number("2")])
        // By name, the first entry.
        #expect(try JSONPathQuery("$.a").evaluate(object).map(\.ordinals) == [[0]])
        let nested = try JSONPathQuery("$..b").evaluate(JSONValue.parse(#"{"x": [0, {"a": 1, "b": 2}]}"#)!)
        #expect(nested.map(\.ordinals) == [[0, 1, 1]])
    }

    @Test func resultsCarryTheirValues() throws {
        let results = try JSONPathQuery("$.backtrace[*].line").evaluate(context)
        #expect(results.map(\.value) == ["80", "118", "603", "552", "479"].map(JSONValue.number))
    }

    @Test(arguments: [
        ("$.", "Expected a name or * at 3"),
        ("$.backtrace[", "Expected a selector at 13"),
        ("$.backtrace[0", "Expected , or ] at 14"),
        ("$[?@.line >]", "Expected a value to compare at 12"),
        ("$['open", "Unclosed string at 3"),
        ("method", "A query starts with $ at 1"),
        ("$[?nope(@)]", "Unknown function nope at 4"),
        ("$.a b", "Unexpected b at 5"),
        (#"$[?search(@, '\d+')]"#, #"Bad escape \d: write \\d for a regex escape at 15"#),
    ])
    func mistakesSayWhatAndWhere(query: String, message: String) {
        #expect(throws: JSONPathError(message: message)) { try JSONPathQuery(query) }
    }
}
