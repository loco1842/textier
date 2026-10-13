import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Go to Line and the app's shortcuts", .serialized)
    struct ShortcutsTests {
        static let text = "first line\nsecond line\nthird line here\nlast"

        @Test func commandGGoesToALineAndColumn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Self.text)

                #expect(app.shortcut("g"))
                let bar = try #require(GoToLineBar.current)
                #expect(bar.field.placeholderString == "Go to line (1–4), or line:column")
                bar.field.stringValue = "3:7"
                bar.go()
                #expect(GoToLineBar.current == nil)
                #expect(app.panel.firstResponder === app.textView)
                let third = (Self.text as NSString).range(of: "third line here").location
                #expect(app.textView.selectedRange() == NSRange(location: third + 6, length: 0))

                // Past the end: the last line.
                app.shortcut("g")
                GoToLineBar.current?.field.stringValue = "99"
                GoToLineBar.current?.go()
                #expect(app.textView.selectedRange().location == (Self.text as NSString).range(of: "last").location)
            }
        }

        @Test func somethingThatIsntALineKeepsTheBarOpenAndEscClosesIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Self.text)
                app.textView.setSelectedRange(NSRange(location: 2, length: 0))

                app.shortcut("g")
                let bar = try #require(GoToLineBar.current)
                bar.field.stringValue = "two"
                bar.go()
                #expect(GoToLineBar.current === bar)
                #expect(app.textView.selectedRange().location == 2)

                _ = bar.control(bar.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
                #expect(GoToLineBar.current == nil)
                #expect(app.textView.selectedRange().location == 2)
            }
        }

        @Test func thePanelsShortcutsComeFromTheConfig() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                var config = Config.default
                config.shortcuts[.goToLine] = Shortcut("ctrl+g")
                config.shortcuts[.toggleHighlighting] = nil
                config.shortcuts[.toggleWrapLines] = Shortcut("cmd+option+w")
                config.shortcuts.selectTab = [.option]
                try app.writeConfig(config)
                app.capture(AppFixtures.monologLine)

                #expect(!app.shortcut("g"))
                #expect(GoToLineBar.current == nil)
                #expect(app.shortcut("g", [.control]))
                GoToLineBar.current?.close()

                #expect(!app.shortcut("e"))
                #expect(app.model.highlighting)
                let wraps = app.model.wrapsLines
                #expect(app.shortcut("w", [.command, .option]))
                #expect(app.model.wrapsLines != wraps)

                #expect(!app.shortcut("3"))
                #expect(app.shortcut("3", [.option]))
                #expect(app.selectedTabTitle == app.inspection.tabs[2].title)
            }
        }

        @Test func aMatchWindowGoesToALineInRaw() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                try app.runAction("Pop Out")
                let controller = try #require(app.matchWindows.last)
                #expect(controller.model.mode == .parsed)

                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: controller.window.windowNumber, context: nil, characters: "g", charactersIgnoringModifiers: "g",
                    isARepeat: false, keyCode: UInt16(ShortcutKeys.codes["g"]!)
                )!
                #expect(controller.window.performKeyEquivalent(with: event))
                app.spin(0.3)
                #expect(controller.model.mode == .raw)
                let bar = try #require(GoToLineBar.current)
                bar.field.stringValue = "3"
                bar.go()
                let editor = try #require(controller.rawEditor)
                let lines = LineNumberRuler.lineStarts(in: editor.string as NSString)
                #expect(editor.selectedRange().location == lines[2])
            }
        }

        // MARK: Settings

        @Test func aCommandsShortcutIsRecordedAndAConflictStaysADraft() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                settings.recordShortcut(for: .goToLine, modifiers: [.control], key: "g")
                #expect(app.configText.contains(#""goToLine": "ctrl+g""#))
                #expect(settings.config.shortcuts[.goToLine] == Shortcut("ctrl+g"))

                settings.recordShortcut(for: .goToLine, modifiers: [.command], key: "e")
                #expect(settings.draft(.commandShortcut(.goToLine))?.problem == "⌘E is already Toggle Highlighting")
                settings.recordShortcut(for: .goToLine, modifiers: [.command], key: "v")
                #expect(settings.draft(.commandShortcut(.goToLine))?.problem == "⌘V is for editing text")
                settings.recordShortcut(for: .goToLine, modifiers: [.control, .option], key: "t")
                #expect(settings.draft(.commandShortcut(.goToLine))?.problem == "⌃⌥T is the shortcut that opens the Selection Popover")
                #expect(settings.config.shortcuts[.goToLine] == Shortcut("ctrl+g"))

                // The global shortcut can't take a command's either.
                settings.recordShortcut(modifiers: [.command], key: "l")
                #expect(settings.draft(.shortcut)?.problem == "⌘L is already Switch Inspector Layout")

                settings.clearShortcut(of: .popOut)
                #expect(app.configText.contains(#""popOut": """#))
                settings.resetShortcut(of: .goToLine)
                #expect(settings.config.shortcuts[.goToLine] == Shortcut("cmd+g"))
                #expect(settings.draft(.commandShortcut(.goToLine)) == nil)

                settings.setMatchClickModifiers([.option])
                settings.restoreDefaultShortcuts()
                #expect(settings.config.shortcuts == .default)
                #expect(settings.config.shortcut == .default)
            }
        }

        @Test func theMenuBarIconsMenuShowsTheShortcuts() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                var config = Config.default
                config.shortcuts[.settings] = Shortcut("ctrl+option+s")
                config.shortcuts[.quit] = nil
                try app.writeConfig(config)
                let controller = SelectionPopoverController(openInPanel: { _ in }, openPanel: {})
                let menu = controller.menu()
                let settings = try #require(menu.items.first { $0.title == "Settings…" })
                #expect(settings.keyEquivalent == "s")
                #expect(settings.keyEquivalentModifierMask == [.control, .option])
                #expect(menu.items.first { $0.title == "Quit" }?.keyEquivalent == "")
            }
        }
    }
}
