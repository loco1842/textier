import Testing
import TextierCore

@Suite("JSON Viewer row text: previews and search")
struct JSONViewerTextTests {
    let context = JSONValue.parse(Fixtures.monologContextJSON)!

    // MARK: Previews

    @Test func aCollapsedBacktraceFrameReadsAsFileLineAndFunction() {
        guard case .array(let frames)? = context["backtrace"] else {
            Issue.record("no backtrace")
            return
        }
        #expect(frames[0].collapsedPreview == "{ EmailTemplateService.php:80 › __call() }")
    }

    @Test func aFrameWithoutAFunctionStopsAtItsLine() {
        let frame = JSONValue.parse(#"{"file": "/tmp/app.php", "line": 12}"#)!
        #expect(frame.collapsedPreview == "{ app.php:12 }")
    }

    @Test func aCollapsedObjectListsItsFirstFourKeys() {
        #expect(context.collapsedPreview == "{ url, repository, method, scope_count, … }")
        #expect(JSONValue.parse(#"{"a": 1, "b": 2}"#)!.collapsedPreview == "{ a, b }")
        #expect(JSONValue.parse("{}")!.collapsedPreview == "{ }")
    }

    @Test func aCollapsedArrayCountsItsItems() {
        #expect(context["backtrace"]?.collapsedPreview == "[ 5 items ]")
        #expect(JSONValue.parse("[1]")!.collapsedPreview == "[ 1 item ]")
    }

    @Test func anOpenContainerCountsItsEntries() {
        #expect(context.openSummary == "8 keys")
        #expect(JSONValue.parse(#"{"a": 1}"#)!.openSummary == "1 key")
        #expect(context["backtrace"]?.openSummary == "5 items")
    }

    @Test func leavesHaveNoPreview() {
        #expect(JSONValue.string("x").collapsedPreview == nil)
        #expect(JSONValue.number("1").openSummary == "")
    }

    // MARK: Search

    @Test func aKeyMatchesWhateverItsValueIgnoringCase() {
        #expect(jsonSearchMatches(key: "caller_FILE", value: .number("1"), query: "Caller_f"))
        #expect(jsonSearchMatches(key: "backtrace", value: context["backtrace"]!, query: "trace"))
    }

    @Test func aLeafMatchesOnItsValueText() {
        #expect(jsonSearchMatches(key: "x", value: .string("/a/EmailTemplateService.php"), query: "templateservice"))
        #expect(jsonSearchMatches(key: "line", value: .number("603"), query: "60"))
        #expect(jsonSearchMatches(key: "ok", value: .bool(true), query: "tru"))
        #expect(jsonSearchMatches(key: "v", value: .null, query: "null"))
    }

    @Test func aContainersEntriesDontMakeItMatch() {
        // Its children match on their own; the container shows as their parent.
        #expect(!jsonSearchMatches(key: "frame", value: JSONValue.parse(#"{"file": "x.php"}"#)!, query: "x.php"))
    }

    @Test func theRootKeyAndABlankQueryMatchNothing() {
        #expect(!jsonSearchMatches(key: nil, value: .string("abc"), query: "zzz"))
        #expect(jsonSearchMatches(key: nil, value: .string("abc"), query: "ab"))
        #expect(!jsonSearchMatches(key: "abc", value: .string("abc"), query: "  "))
    }
}
