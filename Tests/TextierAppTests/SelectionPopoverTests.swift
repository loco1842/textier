import AppKit
import SwiftUI
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("The Selection Popover")
    struct SelectionPopoverTests {
        @Test func itInspectsTheSelectionAndANewOne() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: AppFixtures.monologLine)
                #expect(popover.text == AppFixtures.monologLine)
                #expect(popover.inspector.inspection.tabs.map(\.title) == ["datetime", "json", "url", "file path", "Plain Text"])
                #expect(popover.subtitle == "1 line · selected just now")
                // The preview shows the text with its pills.
                #expect(popover.preview.string == AppFixtures.monologLine)
                #expect(popover.preview.pills.count == popover.inspector.inspection.matches.count)

                popover.show(selection: "see https://x.test\nand /tmp/app.log:3")
                #expect(popover.inspector.inspection.tabs.map(\.title) == ["url", "file path", "Plain Text"])
                #expect(popover.subtitle.hasPrefix("2 lines · "))
            }
        }

        @Test func theListHasEveryMatchInTextOrderAndAChipFiltersIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")

                #expect(popover.rows.map(\.entry.text) == ["https://x.test", "2026-10-07 11:17:10", "https://y.test"])
                // Plain Text isn't in the list.
                #expect(!popover.rows.contains { $0.tab.id == .plainText })

                popover.filter = .pattern("url")
                #expect(popover.rows.map(\.entry.text) == ["https://x.test", "https://y.test"])
                // A pill clicked outside the filter shows everything again, selected.
                let datetime = try #require(popover.inspector.inspection.matches.first { $0.patternName == "datetime" })
                popover.preview.onClick(datetime)
                #expect(popover.filter == nil)
                #expect(popover.inspector.selectedEntry?.text == "2026-10-07 11:17:10")

                // A new selection shows every Match.
                popover.filter = .pattern("url")
                popover.show(selection: "https://z.test then 2026-10-08 09:00:00")
                #expect(popover.filter == nil)
                #expect(popover.rows.count == 2)
            }
        }

        @Test func aChipHidingTheSelectionSelectsItsFirstRow() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")
                popover.select(popover.rows[1])

                popover.show(only: .pattern("url"))
                #expect(popover.inspector.selectedEntry?.text == "https://x.test")
                // A selection the filter shows stays.
                popover.select(popover.rows[1])
                popover.show(only: nil)
                #expect(popover.inspector.selectedEntry?.text == "https://y.test")
            }
        }

        @Test func aChipMovedIsTheTabOrderThePanelKeepsToo() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let popover = SelectionPopoverModel()
                popover.show(selection: AppFixtures.monologLine)
                #expect(popover.inspector.patternTabs.map(\.title) == ["datetime", "json", "url", "file path"])

                popover.inspector.moveTab(named: "url", to: 0)
                #expect(popover.inspector.patternTabs.map(\.title) == ["url", "datetime", "json", "file path"])
                // The open Panel follows at once, and the order is kept.
                #expect(app.model.patternTabs.map(\.title) == ["url", "datetime", "json", "file path"])
                #expect(UserDefaults.standard.stringArray(forKey: PanelModel.tabOrderKey)?.first == "url")
            }
        }

        @Test func theListStopsAtItsLargestAndCountsTheRest() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let count = SelectionPopoverModel.largestList + 5
                let popover = SelectionPopoverModel()
                popover.show(selection: (0..<count).map { "https://x.test/\($0)" }.joined(separator: "\n"))

                #expect(popover.rows.count == SelectionPopoverModel.largestList)
                #expect(popover.hiddenRowCount == 5)
            }
        }

        @Test func aRowClickedIsSelectedItsCopyButtonCopiesAndTheArrowsMoveDownTheList() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")

                // A click selects; its Copy button copies.
                popover.select(popover.rows[2])
                #expect(popover.inspector.selectedEntry?.text == "https://y.test")
                #expect(app.pasteboard.string(forType: .string) != "https://y.test")
                popover.run(.action(.copy), on: popover.rows[2])
                #expect(app.pasteboard.string(forType: .string) == "https://y.test")
                #expect(popover.preview.pills.contains { $0.hasRing && $0.range == popover.rows[2].entry.range })

                popover.moveSelection(by: -1)
                #expect(popover.inspector.selectedEntry?.text == "2026-10-07 11:17:10")
                popover.moveSelection(by: -5)
                #expect(popover.inspector.selectedEntry?.text == "https://x.test")
                popover.moveSelection(by: 9)
                #expect(popover.inspector.selectedEntry?.text == "https://y.test")
            }
        }

        @Test func aRowClickedOpensOnItsCardOneAtATime() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")
                #expect(popover.openRow == nil)

                popover.toggle(popover.rows[0])
                #expect(popover.openRow == popover.rows[0].id)
                #expect(popover.inspector.selectedEntry?.text == "https://x.test")
                // Opening another closes the first.
                popover.toggle(popover.rows[2])
                #expect(popover.openRow == popover.rows[2].id)
                #expect(popover.inspector.selectedEntry?.text == "https://y.test")
                // Clicked again, it closes and stays selected.
                popover.toggle(popover.rows[2])
                #expect(popover.openRow == nil)
                #expect(popover.inspector.selectedEntry?.text == "https://y.test")
                // Nothing copied along the way.
                #expect(app.pasteboard.string(forType: .string) != "https://y.test")
            }
        }

        @Test func theKeysOpenAndCloseRowsAndAnOpenCardFollowsTheSelection() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")
                popover.select(popover.rows[0])

                // Closed, Down only moves.
                popover.moveSelection(by: 1)
                #expect(popover.openRow == nil)
                // Right opens the selected row, and the open card follows Up and Down.
                popover.openSelection()
                #expect(popover.openRow == popover.rows[1].id)
                popover.moveSelection(by: 1)
                #expect(popover.openRow == popover.rows[2].id)
                popover.moveSelection(by: -2)
                #expect(popover.openRow == popover.rows[0].id)
                // Left closes it, and the selection stays.
                popover.closeOpenRow()
                #expect(popover.openRow == nil)
                #expect(popover.inspector.selectedEntry?.text == "https://x.test")
                // Space toggles.
                popover.toggleSelection()
                #expect(popover.openRow == popover.rows[0].id)
                popover.toggleSelection()
                #expect(popover.openRow == nil)

                // A pill only selects while nothing is open; with a card open, its row opens.
                let pills = popover.inspector.inspection.matches
                let datetime = try #require(pills.first { $0.patternName == "datetime" })
                let y = try #require(pills.first { $0.text == "https://y.test" })
                popover.preview.onClick(datetime)
                #expect(popover.openRow == nil)
                #expect(popover.inspector.selectedEntry?.text == "2026-10-07 11:17:10")
                popover.openSelection()
                popover.preview.onClick(y)
                #expect(popover.openRow == popover.rows[2].id)
            }
        }

        @Test func theOpenRowClosesWhenItLeavesTheListOrANewSelectionComes() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")

                // A chip hiding it.
                popover.toggle(popover.rows[2])
                popover.show(only: .pattern("datetime"))
                #expect(popover.openRow == nil)
                // A chip showing it keeps it.
                popover.show(only: nil)
                popover.toggle(popover.rows[2])
                popover.show(only: .pattern("url"))
                #expect(popover.openRow == popover.rows[1].id)
                popover.show(only: nil)

                // An edit elsewhere keeps it; an edit taking it away closes it.
                let end = (popover.preview.string as NSString).length
                popover.preview.insertText(" done", replacementRange: NSRange(location: end, length: 0))
                app.spin(0.3)
                #expect(popover.openRow == popover.rows[2].id)
                let y = (popover.preview.string as NSString).range(of: " and https://y.test")
                popover.preview.insertText("", replacementRange: y)
                app.spin(0.3)
                #expect(popover.rows.count == 2)
                #expect(popover.openRow == nil)

                // A new selection starts closed.
                popover.toggle(popover.rows[0])
                popover.show(selection: "see https://x.test")
                #expect(popover.openRow == nil)
            }
        }

        @Test func anEditKeepsTheOpenRowOnItsMatch() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test at 2026-10-07 11:17:10 and https://y.test")
                @MainActor func openText() -> String? {
                    popover.rows.first { $0.id == popover.openRow }?.entry.text
                }
                popover.toggle(popover.rows[2])
                #expect(openText() == "https://y.test")

                // A URL typed before it shifts the indexes; the card stays on y, with the selection.
                popover.preview.insertText("https://w.test ", replacementRange: NSRange(location: 0, length: 0))
                app.spin(0.3)
                #expect(popover.rows.count == 4)
                #expect(openText() == "https://y.test")
                #expect(popover.openRow == popover.inspector.inspection.selection)
                // Taking a URL before it away keeps it open too.
                let x = (popover.preview.string as NSString).range(of: "https://x.test ")
                popover.preview.insertText("", replacementRange: x)
                app.spin(0.3)
                #expect(popover.rows.count == 3)
                #expect(openText() == "https://y.test")
                // An edit inside it shows the edited Match.
                let host = (popover.preview.string as NSString).range(of: "y.test")
                popover.preview.insertText("yy", replacementRange: NSRange(location: host.location, length: 1))
                app.spin(0.3)
                #expect(openText() == "https://yy.test")
            }
        }

        @Test func anOpenJSONRowShowsItsBeautifiedTextWithLineNumbers() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: AppFixtures.monologLine)
                let row = try #require(popover.rows.first { $0.tab.title == "json" })
                guard case .json(let value) = row.entry.detail else {
                    Issue.record("not JSON")
                    return
                }
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: SelectionPopoverView.size), styleMask: .borderless,
                    backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.contentView = NSHostingView(rootView: SelectionPopoverView(model: popover, openPanel: {}, close: {}))
                window.orderFrontRegardless()
                defer {
                    window.contentView = nil
                    window.orderOut(nil)
                }
                func beautified() -> NSTextView? {
                    func find(_ view: NSView) -> NSTextView? {
                        if let scrollView = view as? NSScrollView, scrollView.verticalRulerView is LineNumberRuler,
                           let text = scrollView.documentView as? NSTextView, text.string == value.prettyPrinted {
                            return text
                        }
                        return view.subviews.lazy.compactMap(find).first
                    }
                    return window.contentView.flatMap(find)
                }
                app.spin(0.2)
                // Closed rows build no card.
                #expect(beautified() == nil)

                popover.toggle(row)
                app.spin(0.3)
                #expect(beautified() != nil)
                popover.closeOpenRow()
                app.spin(0.3)
                #expect(beautified() == nil)
            }
        }

        @Test func thePreviewShowsThreeUnwrappedLinesAndCountsTheRest() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel { _ in }
                popover.show(selection: "one")
                let oneLine = popover.previewHeight
                #expect(popover.hiddenLineCount == 0)
                popover.show(selection: "one\ntwo")
                let line = popover.previewHeight - oneLine
                #expect(line > 15)

                popover.show(selection: (1...5).map { "line \($0) " + String(repeating: "x", count: 300) }.joined(separator: "\n"))
                #expect(popover.hiddenLineCount == 2)
                // Three lines tall, not five.
                #expect(abs(popover.previewHeight - (oneLine + 2 * line)) < 0.5)
                // Long lines run on rather than wrap.
                #expect(!popover.preview.wrapsLines)
                let layoutManager = try #require(popover.preview.layoutManager)
                var lines = 0
                layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
                #expect(lines == 5)
            }
        }

        @Test func everyKindOfLineEndingCounts() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "one\r\ntwo\rthree\nfour")
                #expect(popover.subtitle == "4 lines · selected just now")
            }
        }

        @Test func selectingAnEntryRingsItInThePreview() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: AppFixtures.monologLine)

                let tab = try #require(popover.inspector.inspection.tab(.pattern("url")))
                popover.inspector.select(EntryID(tab: tab.id, index: 0))
                #expect(popover.preview.pills.last?.hasRing == true)
                #expect(popover.preview.pills.last?.range == tab.entries[0].range)
            }
        }

        @Test func openInPanelHandsItTheSelection() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel(openInPanel: { app.controller.show(input: $0) })
                popover.show(selection: "see https://x.test")

                popover.openInPanel()
                app.spin()
                #expect(app.panel.isVisible)
                #expect(app.textView.string == "see https://x.test")
            }
        }

        @Test func noSelectionSaysSoAndShowsNothing() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.pasteboard.clearContents()
                app.pasteboard.setString("see https://x.test", forType: .string)
                let popover = SelectionPopoverModel()
                #expect(!popover.hasCaptured)

                popover.show(selection: nil, lacksAccessibility: true)
                #expect(popover.hasCaptured)
                #expect(popover.lacksAccessibility)
                #expect(popover.text.isEmpty)
                #expect(popover.rows.isEmpty)
                #expect(!popover.inspector.inspection.showsInspector)
                popover.show(selection: nil)
                #expect(!popover.lacksAccessibility)
            }
        }

        @Test func textTypedOrPastedInThePreviewIsInspectedAfterAPause() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                var opened: String?
                let popover = SelectionPopoverModel { opened = $0 }
                #expect(popover.preview.isEditable)

                // Pasted into the empty popover.
                popover.preview.insertText("see https://x.test", replacementRange: NSRange(location: 0, length: 0))
                #expect(popover.text == "see https://x.test")
                app.spin(0.3)
                #expect(popover.rows.map(\.entry.text) == ["https://x.test"])
                #expect(popover.subtitle == "1 line")

                // Typed onto a selection.
                popover.show(selection: "at 2026-10-07 11:17:10")
                let end = (popover.preview.string as NSString).length
                popover.preview.insertText("\nand https://y.test", replacementRange: NSRange(location: end, length: 0))
                app.spin(0.3)
                #expect(popover.rows.map(\.entry.text) == ["2026-10-07 11:17:10", "https://y.test"])
                #expect(popover.subtitle.hasPrefix("2 lines · selected"))
                popover.openInPanel()
                #expect(opened == "at 2026-10-07 11:17:10\nand https://y.test")
            }
        }

        @Test func escInThePreviewClosesThePopover() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                var closed = 0
                popover.onClose = { closed += 1 }
                popover.show(selection: "see https://x.test")
                popover.preview.setSelectedRange(NSRange(location: 0, length: 3))
                popover.preview.cancelOperation(nil)
                #expect(closed == 1)
            }
        }

        @Test func aTextViewsSelectionInTextierIsReadDirectly() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("see https://x.test and more")
                app.panel.makeFirstResponder(app.textView)
                app.textView.setSelectedRange(app.range(of: "https://x.test"))
                #expect(SelectionCapture.ownSelection(in: app.panel) == "https://x.test")
                app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                #expect(SelectionCapture.ownSelection(in: app.panel) == nil)
            }
        }

        @Test func thePlainTextChipListsTheTextBetweenMatches() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: "see https://x.test then more")

                // The list is Matches; Plain Text's pieces come under their own chip.
                #expect(popover.rows.map(\.entry.text) == ["https://x.test"])
                popover.show(only: .plainText)
                #expect(popover.rows.map(\.entry.text) == ["see", "then more"])
                #expect(popover.rows.allSatisfy { $0.tab.id == .plainText })
                // A piece opens on its text, and copies.
                popover.toggle(popover.rows[1])
                #expect(popover.openRow == popover.rows[1].id)
                popover.run(.action(.copy), on: popover.rows[1])
                #expect(app.pasteboard.string(forType: .string) == "then more")
                popover.show(only: nil)
                #expect(popover.rows.map(\.entry.text) == ["https://x.test"])
            }
        }

        @Test func aHugePlainTextCardIsSizedWithoutReadingAllOfIt() async throws {
            try await runInApp {
                let huge = String(repeating: "a line of log text\n", count: 200_000)
                let entry = InspectorEntry(wholeText: huge, actions: [.copy])
                let clock = ContinuousClock()
                var height: CGFloat?
                let elapsed = clock.measure { height = MatchCard.height(of: entry) }
                #expect(height == MatchCard.tallest)
                #expect(elapsed < .milliseconds(50))
            }
        }

        @Test func theMenuBarIconIsATemplateGlyph() {
            #expect(MenuBarGlyph.image.isTemplate)
            #expect(MenuBarGlyph.image.size == NSSize(width: 18, height: 18))
        }

        @Test func veryLargeTextIsLeftForThePanel() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: String(repeating: "x", count: SelectionPopoverModel.largestInspected + 1))
                #expect(popover.isTooLarge)
                #expect(popover.inspector.inspection.tabs.isEmpty)
                #expect(popover.preview.string.isEmpty)
            }
        }

    }
}
