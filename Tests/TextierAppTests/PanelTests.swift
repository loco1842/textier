import AppKit
import Testing
import TextierCore
@testable import Textier

/// The app's tests drive one shared NSApplication, so they run one at a time.
@MainActor
@Suite(.serialized)
struct AppTests {}

extension AppTests {
    @MainActor
    @Suite("The Panel")
    struct PanelTests {
        @Test func aCaptureOpensTheInputBesideTheInspectorWithOneTabPerPatternInLineOrder() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.panel.isVisible)
                #expect(abs(app.panel.frame.width - 1100) < 1)
                #expect(abs((app.panel.contentView?.frame.height ?? 0) - 650) < 30)
                #expect(app.tabTitles == ["datetime", "json", "url", "file path", "Plain Text"])
                #expect(app.inspection.tabs.map(\.entries.count) == [1, 1, 1, 6, 1])
                #expect(!app.controller.inspectorView.isHidden)
                #expect(app.controller.inspectorView.frame.width > 300)
                #expect(app.panel.firstResponder === app.textView)
            }
        }

        @Test func theJSONIsSelectedOnOpenAndShownInTheJSONViewer() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.selectedTabTitle == "json")
                #expect(app.model.selectedEntry?.text == AppFixtures.jsonPayload)
                let outline = try #require(app.outlineView())
                #expect(outline.node(keyPath: "url") != nil)
            }
        }

        @Test func fileFathsAreTaggedWithTheirParentAndPreviewedOnOneLine() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let paths = try #require(app.inspection.tabs.first { $0.title == "file path" }).entries
                #expect(paths.count == 6)
                #expect(paths.allSatisfy { $0.parent?.description == "in json 0" })
                #expect(paths.allSatisfy { !$0.preview.contains("\n") && $0.preview.count <= 81 })
            }
        }

        @Test func plainTextIsTheLogMessageWithoutPunctuationOnlyPieces() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                let plain = try #require(app.inspection.tabs.last)
                #expect(plain.title == "Plain Text")
                #expect(plain.entries.map(\.text) == [
                    "develop.WARNING: [REPOSITORY SCOPE LEAK] __call invoked with non-empty scopeQueries",
                ])
            }
        }

        @Test func selectingANestedEntrySelectsItsExactTextInTheInput() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                try app.select("file path", 3)

                let entry = try #require(app.model.selectedEntry)
                #expect(app.textView.selectedRange() == entry.range)
                #expect((app.textView.string as NSString).substring(with: entry.range).hasSuffix("Dispatcher.php"))
            }
        }

        @Test func plainTextHidesTheInspectorAndAMatchBringsItBackAtItsWidth() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let width = app.controller.inspectorView.frame.width

                app.capture("nothing structured in this sentence at all")
                #expect(app.controller.inspectorView.isHidden)
                #expect(!app.inspection.showsInspector)

                app.type(" https://x.test", at: (app.textView.string as NSString).length)
                #expect(!app.controller.inspectorView.isHidden)
                #expect(abs(app.controller.inspectorView.frame.width - width) < 2)
                #expect(app.tabTitles == ["url", "Plain Text"])
            }
        }

        @Test func escClosesThePanel() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("x")

                _ = app.textView.delegate?.textView?(app.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
                #expect(!app.panel.isVisible)

                app.capture("y")
                app.panel.cancelOperation(nil)
                #expect(!app.panel.isVisible)
            }
        }

        @Test func thePanelIsAMainWindowWithTrafficLightsLevelWithItsHeader() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let window = app.panel

                #expect(window.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable]))
                #expect(window.collectionBehavior.contains(.fullScreenPrimary))
                #expect(window.titleVisibility == .hidden)
                #expect(window.firstResponder === app.textView)
                let close = try #require(window.standardWindowButton(.closeButton))
                #expect(window.standardWindowButton(.miniaturizeButton) != nil)
                #expect(window.standardWindowButton(.zoomButton) != nil)

                // The lights sit mid-header, and a click in the header past them reaches
                // the header, not the title bar.
                let frame = try #require(window.contentView?.superview)
                let lights = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: frame)
                #expect(abs(lights.y - (frame.bounds.maxY - 26)) < 4)
                let header = NSPoint(x: lights.x + 120, y: lights.y)
                let hit = try #require(frame.hitTest(header))
                #expect(hit.isDescendant(of: try #require(window.contentView)))

                // Esc hides it, as before.
                window.cancelOperation(nil)
                #expect(!window.isVisible)
            }
        }

        @Test func itsSizeAndDividerAreRestoredOnTheNextOpen() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                app.panel.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 700), display: true)
                app.spin()
                app.controller.splitView.setPosition(700, ofDividerAt: 0)
                app.spin()
                #expect(abs(app.controller.inspectorView.frame.width - 492) < 2)

                // Both are saved: the window's frame under its autosave name.
                #expect(abs(UserDefaults.standard.double(forKey: PanelController.inspectorWidthKey) - 492) < 2)
                let saved = (UserDefaults.standard.string(forKey: "NSWindow Frame textier.Panel") ?? "")
                    .split(separator: " ").compactMap { Double($0) }
                try #require(saved.count >= 4)
                #expect(abs(saved[2] - 1200) < 1)
                #expect(abs(saved[3] - 700) < 1)

                // Text with nothing to inspect hides the Inspector, so the next Matches
                // bring it back at the saved width.
                app.panel.cancelOperation(nil)
                app.capture("nothing structured in this sentence at all")
                #expect(app.controller.inspectorView.isHidden)
                app.capture(AppFixtures.monologLine)

                #expect(abs(app.panel.frame.width - 1200) < 1)
                #expect(abs(app.panel.frame.height - 700) < 1)
                #expect(abs(app.controller.inspectorView.frame.width - 492) < 2)
            }
        }

        @Test func capsLockAndTheKeypadLeaveTheShortcutsAsTheyAre() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut("e", [.command, .capsLock]))
                #expect(!app.model.highlighting)
                #expect(app.shortcut("1", [.command, .numericPad]))
                #expect(app.selectedTabTitle == "datetime")
            }
        }

        @Test func theHeaderCountsPatternsAndMatches() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.model.countLine == "4 Patterns · 9 Matches")
            }
        }

        @Test func theWarningsBadgeHasEveryWarning() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"{ "patterns": [{ "name": "bad", "regex": "(", "actions": ["copy"] }] }"#)
                defer { app.tearDown() }
                app.capture("x")

                #expect(app.model.warnings.contains { $0.contains("bad") && $0.contains("unbalanced parenthesis") })
            }
        }

        @Test func aPatternStoppedForTakingTooLongWarnsUntilAPassWhereItIsNot() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"{ "patterns": [{ "name": "runaway", "regex": "(a+)+$", "actions": ["copy"] }] }"#)
                defer { app.tearDown() }
                app.capture(String(repeating: "a", count: 40) + "!")

                #expect(app.model.warnings == [
                    #"Pattern "runaway" was stopped after 2 s; some of its Matches may be missing"#
                ])

                app.type("", replacing: NSRange(location: 40, length: 1))
                #expect(app.model.warnings.isEmpty)
                #expect(app.inspection.matches.map(\.patternName) == ["runaway"])
            }
        }

        @Test func aLargeInputIsInspectedInTheBackgroundAndItsMatchesArrive() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let urls = ["https://a.test/1", "https://a.test/2", "https://a.test/3"]
                let input = "see \(urls[0]) " + largeFiller + " then \(urls[1]) and \(urls[2])"
                app.controller.show(input: input)

                // At once: the Panel shows the text, and nothing of the last Inspection.
                #expect(app.panel.isVisible)
                #expect(app.model.isInspecting)
                #expect(app.inspection.matches.isEmpty)
                #expect(app.controller.inspectorView.isHidden)

                app.waitForBackgroundInspection()
                #expect(!app.model.isInspecting)
                #expect(app.inspection.matches.map(\.text) == urls)
                #expect(app.textView.pills.count == 3)
                #expect(app.tabTitles == ["url", "Plain Text"])
                #expect(!app.controller.inspectorView.isHidden)
            }
        }

        @Test func aSelectionMadeDuringABackgroundInspectionIsKept() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let urls = ["https://a.test/1", "https://a.test/2", "https://a.test/3"]
                app.controller.show(input: "see \(urls[0]) " + largeFiller + " then \(urls[1]) and \(urls[2])")
                app.waitForBackgroundInspection()
                #expect(app.inspection.selection == EntryID(tab: .pattern("url"), index: 0))

                // A config reload's inspection finishes in the background, its result not
                // yet taken, and meanwhile the user picks the last URL.
                app.controller.configDidChange()
                PanelModel.inspections.sync {}
                app.model.select(EntryID(tab: .pattern("url"), index: 2))

                app.waitForBackgroundInspection()
                #expect(app.inspection.selection == EntryID(tab: .pattern("url"), index: 2))
                #expect(app.textView.pills.last?.hasRing == true)
                #expect(app.textView.pills.last?.range == app.range(of: urls[2]))
            }
        }

        @Test func anInputJustUnderTheThresholdIsStillInspectedAtOnce() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let url = "https://a.test/1"
                // The URL, a space and the x's: one unit short of the threshold.
                let filler = String(repeating: "x", count: PanelModel.backgroundThreshold - url.count - 2)
                app.controller.show(input: "\(url) \(filler)")

                #expect(!app.model.isInspecting)
                #expect(app.inspection.matches.map(\.text) == [url])

                // One more and it's the background's.
                app.controller.show(input: "\(url) \(filler)x")
                #expect(app.model.isInspecting)
                app.waitForBackgroundInspection()
                #expect(app.inspection.matches.map(\.text) == [url])
            }
        }


        @Test func textOver100MBIsRefusedAndTheInputStaysAsItWas() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture("see https://x.test")
                let huge = String(repeating: "a", count: PanelModel.largestInput + 1)

                // A capture (Open in Panel, the shortcut's fallback).
                app.controller.show(input: huge)
                #expect(app.textView.string == "see https://x.test")
                #expect(app.model.refusal == "Too large for the Panel: 101 MB, the limit is 100 MB")

                // A paste, through the text view.
                app.capture("see https://x.test")
                #expect(app.model.refusal == nil)
                app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                app.textView.insertText(huge, replacementRange: NSRange(location: 0, length: 0))
                #expect(app.textView.string == "see https://x.test")
                #expect(app.model.refusal != nil)

                // Text that fits clears the note.
                app.type("x", at: 0)
                #expect(app.model.refusal == nil)
                #expect(app.textView.string == "xsee https://x.test")
            }
        }

        @Test func aSelectionOver100MBIsntOfferedToThePanel() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let popover = SelectionPopoverModel()
                popover.show(selection: String(repeating: "a", count: SelectionPopoverModel.largestInspected + 1))
                #expect(popover.isTooLarge && !popover.isTooLargeForPanel)
                popover.show(selection: String(repeating: "a", count: PanelModel.largestInput + 1))
                #expect(popover.isTooLargeForPanel)
                popover.clear()
                #expect(!popover.isTooLargeForPanel)
            }
        }
    }
}

/// Plain words just over `PanelModel.backgroundThreshold` UTF-16 units, so an
/// Input with them is inspected in the background.
let largeFiller = String(repeating: "plain words here ", count: PanelModel.backgroundThreshold / 17 + 1)

extension AppHarness {
    /// Spins the run loop until a background inspection has landed, for up to `seconds`.
    func waitForBackgroundInspection(_ seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while model.isInspecting, Date() < deadline { spin() }
    }
}
