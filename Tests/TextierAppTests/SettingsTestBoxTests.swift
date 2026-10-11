import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Settings: the Pattern test box")
    struct SettingsTestBoxTests {
        /// Settings with the `log level` Pattern open in the editor.
        func openLogLevel(_ app: AppHarness) throws -> SettingsModel {
            let settings = try app.openSettings()
            settings.selectedPattern = try #require(settings.config.patterns.firstIndex { $0.name == "log level" })
            return settings
        }

        @Test func itStartsWithThePanelsInput() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try openLogLevel(app)

                #expect(settings.testInput == AppFixtures.monologLine)
            }
        }

        @Test func typingARegexHighlightsItsMatchesWithoutWritingTheFile() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try openLogLevel(app)
                let before = app.configText

                settings.editedRegex = #"develop\.\w+"#
                #expect(try settings.testMatches.get().map(\.text) == ["develop.WARNING"])
                #expect(app.configText == before)
            }
        }

        @Test func selectingAMatchShowsItsFields() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try openLogLevel(app)

                settings.editedRegex = "(?<level>WARNING|ERROR)"
                #expect(try settings.testMatches.get().map(\.text) == ["WARNING"])
                #expect(settings.selectedTestFields.isEmpty)
                settings.selectTestMatch(at: (AppFixtures.monologLine as NSString).range(of: "WARNING").location + 2)
                #expect(settings.selectedTestFields.map(\.label) == ["level"])
                #expect(settings.selectedTestFields.map(\.value) == ["WARNING"])
            }
        }

        @Test func anUnfinishedRegexShowsItsErrorAndNoMatches() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try openLogLevel(app)

                settings.editedRegex = "(?<x"
                guard case .failure(let error) = settings.testMatches else {
                    Issue.record("expected an error")
                    return
                }
                #expect(error.message == "unclosed group name (?<x")
            }
        }

        @Test func theTestBoxTextCanBeEditedAndCommittingTheRegexWritesIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try openLogLevel(app)
                let index = try #require(settings.selectedPattern)

                settings.testInput = "boot INFO ok"
                settings.editedRegex = #"\bINFO\b"#
                #expect(try settings.testMatches.get().map(\.text) == ["INFO"])
                settings.commitEditedRegex()
                #expect(settings.editedRegex == nil)
                #expect(settings.regexText(at: index) == #"\bINFO\b"#)
                #expect(app.configText.contains(#""regex": "\\bINFO\\b""#))
            }
        }

        /// The Matches are kept between asks, and run again whenever the regex, the
        /// text or the Grok Definitions change.
        @Test func theMatchesFollowTheRegexTheTextAndTheDefinitions() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try openLogLevel(app)

                settings.testInput = "fix ABC-12 today"
                settings.editedRegex = "%{MYTICKET}"
                guard case .failure = settings.testMatches else {
                    Issue.record("expected MYTICKET to be unknown")
                    return
                }
                #expect(settings.addGrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#) == nil)
                #expect(try settings.testMatches.get().map(\.text) == ["ABC-12"])
                settings.testInput = "fix ABC-12 and XY-3 today"
                #expect(try settings.testMatches.get().map(\.text) == ["ABC-12", "XY-3"])
                settings.editedRegex = #"[A-Z]+-1\d"#
                #expect(try settings.testMatches.get().map(\.text) == ["ABC-12"])

                // Asked again with nothing changed, the last run is reused, not redone.
                settings.lastTestRun?.matches = .success([])
                #expect(try settings.testMatches.get().isEmpty)
                settings.testInput = "fix ABC-12 again"
                #expect(try settings.testMatches.get().map(\.text) == ["ABC-12"])
            }
        }

        @Test func aCopyInTheTestBoxIsTextiersOwn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try openLogLevel(app)
                settings.section = .patterns
                app.spin(0.2)
                @MainActor func testBox(in view: NSView) -> NSTextView? {
                    if let textView = view as? OwnCopyTextView, textView.isEditable, textView.string == settings.testInput {
                        return textView
                    }
                    return view.subviews.lazy.compactMap(testBox(in:)).first
                }
                let window = try #require(app.settingsWindow).window
                let textView = try #require(window.contentView.flatMap(testBox(in:)))

                textView.setSelectedRange(NSRange(location: 1, length: 19))
                textView.copy(nil)
                #expect(app.copied == "2026-10-07 11:17:10")
                #expect(lastOwnCopy == app.pasteboard.changeCount)
            }
        }

        @Test func aLongPanelInputStartsTheTestBoxWithItsFirstWholeLines() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let line = String(repeating: "x", count: 99) + "\n"
                let input = String(repeating: line, count: 1000)
                app.capture(input)
                let settings = try openLogLevel(app)

                #expect(settings.testInput.count == 65_500)
                #expect(input.hasPrefix(settings.testInput))
                #expect(SettingsModel.testSample(of: AppFixtures.monologLine) == AppFixtures.monologLine)
            }
        }
    }
}
