import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Sorting the Inspector's entries")
    struct SortingTests {
        /// Datetimes out of order: 10:00, 08:00, 12:00, 09:00.
        static let text = "a 2026-10-11 10:00:00 b 2026-10-11 08:00:00 c 2026-10-11 12:00:00 d 2026-10-11 09:00:00"

        /// The datetime rows' texts, top to bottom, as the list shows them.
        @MainActor func shownDatetimes(_ app: AppHarness) throws -> [String] {
            let list = try #require(app.controller.entryList?.delegate as? EntryListController)
            let tab = try #require(app.inspection.tab(.pattern("datetime")))
            return list.rows.compactMap {
                guard case .entry(_, let index) = $0 else { return nil }
                return tab.entries[index].text
            }
        }

        @Test func aTabSortsByItsValuesAndKeepsTheSelection() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Self.text)
                try app.select("datetime", 1)
                app.spin(0.2)
                #expect(try shownDatetimes(app) == [
                    "2026-10-11 10:00:00", "2026-10-11 08:00:00", "2026-10-11 12:00:00", "2026-10-11 09:00:00",
                ])

                app.model.setOrder(.descending, of: .pattern("datetime"))
                app.spin(0.2)
                #expect(try shownDatetimes(app) == [
                    "2026-10-11 12:00:00", "2026-10-11 10:00:00", "2026-10-11 09:00:00", "2026-10-11 08:00:00",
                ])
                // Still the 08:00 entry, now the last row, and the table has it selected.
                #expect(app.model.inspection.selection == EntryID(tab: .pattern("datetime"), index: 1))
                #expect(app.controller.entryList?.selectedRow == 3)

                // The arrows go by the shown order.
                app.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
                app.spin(0.2)
                app.pressUp()
                #expect(app.model.selectedEntry?.text == "2026-10-11 09:00:00")
            }
        }

        @Test func editsAndReloadsKeepTheOrderAndNewTextResetsIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Self.text)
                app.model.setOrder(.ascending, of: .pattern("datetime"))

                app.type("x ", at: 0)
                #expect(app.model.order(of: .pattern("datetime")) == .ascending)
                try app.writeConfig(Config.default)
                #expect(app.model.order(of: .pattern("datetime")) == .ascending)

                app.capture(Self.text)
                #expect(app.model.order(of: .pattern("datetime")) == .position)

                // A paste over everything is new text too.
                app.model.setOrder(.ascending, of: .pattern("datetime"))
                app.type(Self.text, replacing: NSRange(location: 0, length: (app.textView.string as NSString).length))
                #expect(app.model.order(of: .pattern("datetime")) == .position)
            }
        }

        @Test func thePopoversChipListSortsTooAndANewSelectionResetsIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: Self.text)
                popover.show(only: .pattern("datetime"))
                popover.sort(.ascending)
                #expect(popover.rows.map(\.entry.text) == [
                    "2026-10-11 08:00:00", "2026-10-11 09:00:00", "2026-10-11 10:00:00", "2026-10-11 12:00:00",
                ])
                // Unfiltered, the list is in text order.
                popover.show(only: nil)
                #expect(popover.rows.first?.entry.text == "2026-10-11 10:00:00")

                popover.show(selection: Self.text)
                #expect(popover.inspector.order(of: .pattern("datetime")) == .position)
            }
        }
    }
}
