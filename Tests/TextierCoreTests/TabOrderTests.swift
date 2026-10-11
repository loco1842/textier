import Testing
import TextierCore

@Suite("Tab order the user arranged")
struct TabOrderTests {
    func tab(_ id: InspectorTab.ID) -> InspectorTab {
        let title = if case .pattern(let name) = id { name } else { "Plain Text" }
        return InspectorTab(id: id, title: title, color: nil, glyph: .plainText, entries: [])
    }

    func titles(_ tabs: [InspectorTab]) -> [String] { tabs.map(\.title) }

    let found = [InspectorTab.ID.pattern("datetime"), .pattern("json"), .pattern("url"), .plainText]

    @Test func namedPatternsComeFirstInTheArrangedOrder() {
        let tabs = arrangedTabs(found.map(tab), order: ["url", "datetime"])
        #expect(titles(tabs) == ["url", "datetime", "json", "Plain Text"])
    }

    @Test func patternsNotArrangedKeepTheirOrderAfterThoseThatAre() {
        let tabs = arrangedTabs(found.map(tab), order: ["json"])
        #expect(titles(tabs) == ["json", "datetime", "url", "Plain Text"])
    }

    @Test func namesWithNoTabAreSkippedAndPlainTextStaysLast() {
        let tabs = arrangedTabs(found.map(tab), order: ["Plain Text", "file path", "url"])
        #expect(titles(tabs) == ["url", "datetime", "json", "Plain Text"])
    }

    @Test func movingATabRearrangesTheNamesKeepingOnesNotShown() {
        // file path was arranged before, and isn't in this Input.
        let order = arrangingTab("url", to: 0, shown: ["datetime", "json", "url"], order: ["file path", "json"])
        #expect(order == ["url", "datetime", "json", "file path"])
        #expect(arrangingTab("datetime", to: 2, shown: ["datetime", "json", "url"], order: []) == ["json", "url", "datetime"])
        #expect(arrangingTab("nope", to: 0, shown: ["json"], order: ["json"]) == ["json"])
    }
}
