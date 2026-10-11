import AppKit
import Carbon.HIToolbox
import Testing
import TextierCore
@testable import Textier

extension AppHarness {
    /// Opens Settings with ⌘, in the Panel and returns its model.
    func openSettings() throws -> SettingsModel {
        if !panel.isVisible { capture("") }
        #expect(shortcut(","))
        return try #require(settingsWindow).model
    }
}

extension AppTests {
    @MainActor
    @Suite("Settings")
    struct SettingsTests {
        static let ctrlOptionY = Shortcut("ctrl+option+y")!

        // MARK: The window

        @Test func commandCommaInThePanelOpensOneSettingsWindow() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)

                #expect(app.shortcut(","))
                let settings = try #require(app.settingsWindow)
                #expect(settings.window.isVisible)
                #expect(settings.model.section == .general)

                #expect(app.shortcut(","))
                #expect(app.settingsWindow === settings)
                #expect(NSApp.windows.filter { $0.isVisible && $0.title == settings.window.title }.count == 1)
            }
        }

        @Test func aClosedSettingsWindowOpensAfreshOnTheNextShow() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                _ = try app.openSettings()
                let first = try #require(app.settingsWindow)

                first.window.close()
                app.spin()
                #expect(app.settingsWindow == nil)
                _ = try app.openSettings()
                #expect(app.settingsWindow !== first)
            }
        }

        // MARK: General

        @Test func recordingTheShortcutWritesItAndRegistersIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(app.registeredShortcuts == [.default])

                settings.recordShortcut(modifiers: [.control, .option], key: "y")
                #expect(app.configText.contains(#""shortcut": "ctrl+option+y""#))
                #expect(settings.config.shortcut == Self.ctrlOptionY)
                #expect(app.registeredShortcuts.last == Self.ctrlOptionY)
                #expect(settings.draft(.shortcut) == nil)
                #expect(settings.warnings(in: .general).isEmpty)
            }
        }

        @Test func aShortcutThatCantBeRegisteredSaysSoInGeneral() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                app.takenShortcuts = [Self.ctrlOptionY]

                settings.setShortcut(Self.ctrlOptionY)
                #expect(app.configText.contains(#""shortcut": "ctrl+option+y""#))
                // Tried, then the previous one put back.
                #expect(app.registeredShortcuts.suffix(2) == [Self.ctrlOptionY, .default])
                let general = settings.warnings(in: .general).map(\.message)
                #expect(general.count == 1)
                #expect(general.first?.contains("Couldn't register the shortcut ctrl+option+y") == true)
                #expect(general.first?.contains("still using ctrl+option+t") == true)
                #expect(settings.warnings(in: .appearance).isEmpty)
            }
        }

        @Test func anInvalidShortcutStaysADraftAndIsntWritten() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let before = app.configText

                settings.recordShortcut(modifiers: [.shift], key: "y")
                let draft = try #require(settings.draft(.shortcut))
                #expect(draft.text == "⇧Y")
                #expect(draft.problem.contains("⌃, ⌥ or ⌘"))
                #expect(!draft.fileChanged)
                #expect(app.configText == before)
                #expect(settings.config.shortcut == .default)

                settings.recordShortcut(modifiers: [.control], key: "-")
                #expect(settings.draft(.shortcut)?.text == "⌃-")
                #expect(app.configText == before)

                settings.discardDraft(.shortcut)
                #expect(settings.draft(.shortcut) == nil)
            }
        }

        @Test func aValidShortcutReplacesTheDraft() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                settings.recordShortcut(modifiers: [.shift], key: "y")
                settings.recordShortcut(modifiers: [.control, .option], key: "y")
                #expect(settings.draft(.shortcut) == nil)
                #expect(app.configText.contains(#""shortcut": "ctrl+option+y""#))
            }
        }

        @Test func clearingTheSelectionAfterAWhileIsWrittenToTheFile() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.config.clearSelectionAfter == 0)
                #expect(settings.clearSelectionChoices.map(SettingsModel.clearSelectionTitle) == [
                    "Never", "After 30 seconds", "After 1 minute", "After 5 minutes", "After 15 minutes", "After 1 hour",
                ])

                settings.setClearSelectionAfter(300)
                #expect(app.configText.contains(#""clearSelectionAfter": 300"#))
                #expect(app.store.config.clearSelectionAfter == 300)

                // A value of the file's own shows among the choices.
                var config = Config.default
                config.clearSelectionAfter = 45
                try app.writeConfig(config)
                #expect(settings.clearSelectionChoices.contains(45))
                #expect(SettingsModel.clearSelectionTitle(45) == "After 45 seconds")
            }
        }

        @Test func changingCopyJSONWritesTheFileAndThePanelFollows() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try app.openSettings()

                settings.setCopyJSON(.pretty)
                #expect(app.configText.contains(#""copyJSON": "pretty""#))
                #expect(settings.config.copyJSON == .pretty)
                app.panel.makeKeyAndOrderFront(nil)
                app.doubleClick(onText: #""method""#)
                #expect(app.copied == JSONValue.parse(AppFixtures.jsonPayload)?.prettyPrinted)
            }
        }

        @Test func editingAPatternInSettingsKeepsItsColorRules() async throws {
            try await runInApp {
                let app = try AppHarness(config: ##"""
                { "patterns": [{ "name": "status", "regex": "\\b[1-5]\\d\\d\\b", "actions": ["copy"],
                  "colors": [{ "when": "^5", "color": "#e5484d" }, { "when": "^4", "color": "#ef5f00" }] }] }
                """##)
                defer { app.tearDown() }
                let settings = try app.openSettings()

                settings.setPatternName("http status", at: 0)
                let rules = try #require(app.store.config.patterns.first).colorRules
                #expect(rules?.map(\.when) == ["^5", "^4"])
                #expect(app.configText.contains(#""when": "^5""#))
            }
        }

        @Test func aColorRuleThatDidntLoadIsKeptAsWrittenWhenSettingsWrites() async throws {
            try await runInApp {
                let app = try AppHarness(config: ##"""
                { "patterns": [
                  { "name": "status", "regex": "\\b[1-5]\\d\\d\\b", "actions": ["copy"],
                    "colors": [{ "when": "(5", "color": "#e5484d" }, { "when": "^4", "color": "#ef5f00" }] },
                  { "name": "ticket", "regex": "[A-Z]+-\\d+", "actions": ["copy"] }
                ] }
                """##)
                defer { app.tearDown() }
                let warning = #"Pattern "status": color rule #1's "when": unbalanced parenthesis (at character 2); skipped"#
                #expect(app.store.warnings.map(\.message).contains(warning))
                let settings = try app.openSettings()

                // The rule stays with its Pattern as it moves.
                settings.movePatterns(from: [0], to: 2)
                settings.setPatternName("http status", at: 1)
                #expect(app.store.config.patterns.map(\.name) == ["ticket", "http status"])
                let text = app.configText
                let status = try #require(text.range(of: #""http status""#)).lowerBound
                let broken = try #require(text.range(of: ##"{ "when": "(5", "color": "#e5484d" }"##)).lowerBound
                #expect(status < broken)
                let renamed = warning.replacingOccurrences(of: #""status""#, with: #""http status""#)
                #expect(app.store.warnings.map(\.message).contains(renamed))
            }
        }

        @Test func changingTheInspectorLayoutWritesTheFileAndThePanelFollows() async throws {
            try await runInApp {
                let app = try AppHarness.withLayout(.tabs)
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try app.openSettings()

                settings.setInspectorLayout(.list)
                #expect(app.configText.contains(#""inspectorLayout": "list""#))
                #expect(app.model.layout == .list)
            }
        }

        @Test func theEditorCommandIsWrittenAndTestOpensTheConfigFile() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                settings.setEditorCommand("zed {path}:{line}")
                #expect(app.configText.contains(#""editorCommand": "zed {path}:{line}""#))
                #expect(settings.config.editorCommand == "zed {path}:{line}")
                settings.testEditorCommand()
                #expect(app.openedFiles == [FileLocation(path: app.store.fileURL.path)])

                settings.setEditorCommand("")
                #expect(app.configText.contains(#""editorCommand": """#))
                #expect(settings.config.editorCommand == nil)
            }
        }

        @Test func anEditorCommandThatWontRunShowsTheWarningInGeneralAfterTest() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                app.editorFailure = "command not found"

                settings.setEditorCommand("no-such-editor {path}")
                #expect(settings.warnings(in: .general).isEmpty)
                settings.testEditorCommand()
                let general = settings.warnings(in: .general).map(\.message)
                #expect(general.count == 1)
                #expect(general.first?.contains("command not found") == true)
                #expect(settings.warnings(in: .appearance).isEmpty)
            }
        }

        // MARK: Appearance

        @Test func theAppearanceSwitchWritesTheFileAndTheAppFollows() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer {
                    app.tearDown()
                    NSApp.appearance = nil
                }
                let settings = try app.openSettings()
                #expect(settings.config.appearance == .system)
                #expect(NSApp.appearance == nil)

                settings.setAppearance(.dark)
                #expect(app.configText.contains(#""appearance": "dark""#))
                #expect(NSApp.appearance?.name == .darkAqua)

                settings.setAppearance(.light)
                #expect(NSApp.appearance?.name == .aqua)

                settings.setAppearance(.system)
                #expect(NSApp.appearance == nil)
                #expect(settings.warnings(in: .appearance).isEmpty)
            }
        }

        @Test func anOldThemeKeyWarnsInAppearanceAndTheGitHubThemesStay() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"{ "theme": { "dark": "mine.json" }, "patterns": [] }"#)
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.warnings(in: .appearance).map(\.message).first?.hasPrefix(#""theme" is ignored"#) == true)
                #expect(app.store.darkTheme == .githubDark)
                #expect(app.store.lightTheme == .githubLight)
            }
        }

        // MARK: Following the file

        @Test func savingTheFileOutsideUpdatesTheModel() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                var config = Config.default
                config.copyJSON = .pretty
                config.shortcut = Self.ctrlOptionY
                try app.writeConfig(config)
                #expect(settings.config.copyJSON == .pretty)
                #expect(settings.config.shortcut == Self.ctrlOptionY)
                #expect(app.registeredShortcuts.last == Self.ctrlOptionY)
            }
        }

        @Test func aSaveThatRenamesOverTheFileReloadsItAndTheWatchGoesOn() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                // No `reload()` here: the file watcher has to notice.
                // As an editor saves: a new file renamed over the old one.
                var config = Config.default
                config.copyJSON = .pretty
                let saved = app.folder.appendingPathComponent("config.json.saving")
                try ConfigFile.encode(config).write(to: saved)
                #expect(rename(saved.path, app.store.fileURL.path) == 0)
                for _ in 0..<40 where app.store.config.copyJSON != .pretty { app.spin(0.05) }
                #expect(app.store.config.copyJSON == .pretty)

                // The watch moved to the new file, so a write in place is seen too.
                config.copyJSON = .raw
                try ConfigFile.encode(config).write(to: app.store.fileURL)
                for _ in 0..<40 where app.store.config.copyJSON != .raw { app.spin(0.05) }
                #expect(app.store.config.copyJSON == .raw)
            }
        }

        @Test func aConfigFileLinkedFromElsewhereStaysALinkWhenSettingsWrites() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                // A config kept in a dotfiles repo, linked from where textier looks.
                let target = app.folder.appendingPathComponent("dotfiles-config.json")
                let link = app.folder.appendingPathComponent("linked-config.json")
                try ConfigFile.encode(Config.default).write(to: target)
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
                let store = ConfigStore(fileURL: link)

                var config = Config.default
                config.copyJSON = .pretty
                try store.write(config)
                #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
                #expect(String(decoding: try Data(contentsOf: target), as: UTF8.self).contains(#""copyJSON": "pretty""#))
                #expect(store.config.copyJSON == .pretty)
            }
        }

        @Test func aBrokenDraftSurvivesAnOutsideSaveWithAFileChangedNote() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.recordShortcut(modifiers: [.shift], key: "y")

                // Settings' own writes aren't changes from outside.
                settings.setCopyJSON(.pretty)
                #expect(settings.draft(.shortcut)?.fileChanged == false)

                var config = Config.default
                config.shortcut = Self.ctrlOptionY
                try app.writeConfig(config)
                let draft = try #require(settings.draft(.shortcut))
                #expect(draft.text == "⇧Y")
                #expect(draft.fileChanged)
                #expect(settings.config.shortcut == Self.ctrlOptionY)
                #expect(settings.config.copyJSON == .raw)

                // A valid press settles it.
                settings.recordShortcut(modifiers: [.control, .option], key: "t")
                #expect(settings.draft(.shortcut) == nil)
                #expect(app.configText.contains(#""shortcut": "ctrl+option+t""#))
            }
        }

        @Test func editsAreRefusedWhileTheFileCantBeUsed() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                try app.writeConfig(#"{ "patterns": [ "#)
                settings.setCopyJSON(.pretty)
                #expect(app.configText == #"{ "patterns": [ "#)
                #expect(settings.writeError != nil)
                #expect(settings.warnings(in: .general).contains { $0.isFatal })

                try app.writeConfig(Config.default)
                #expect(settings.writeError == nil)
                settings.setCopyJSON(.pretty)
                #expect(app.configText.contains(#""copyJSON": "pretty""#))
            }
        }

        // MARK: Warnings

        @Test func configWarningsLandInTheSectionTheyAreAbout() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                {
                  "shortcut": "t",
                  "copyJSON": "fancy",
                  "appearance": "sepia",
                  "patterns": [
                    { "name": "json", "builtin": "json", "actions": ["copy"] },
                    { "name": "ticket", "regex": "(", "actions": ["copy"] }
                  ],
                  "grok": { "LOOP": "%{LOOP}" }
                }
                """#)
                defer { app.tearDown() }
                let settings = try app.openSettings()

                let general = settings.warnings(in: .general).map(\.message)
                #expect(general.count == 2)
                #expect(general.contains { $0.hasPrefix("Shortcut") })
                #expect(general.contains { $0.contains("copyJSON") })
                #expect(settings.warnings(in: .appearance).map(\.message).count == 1)
                #expect(settings.warnings(in: .patterns).map(\.message) == [
                    #"Pattern "ticket": unbalanced parenthesis (at character 1); skipped"#,
                ])
                #expect(settings.warnings(in: .grokDefinitions).map(\.message) == [
                    "Grok Definition LOOP: grok definitions loop: LOOP → LOOP; skipped",
                ])
            }
        }

        @Test func aWarningsSectionComesFromWhatItNames() {
            let section = SettingsModel.section(forLoadWarning:)
            #expect(section(#"Pattern "url": invalid regex; skipped"#) == .patterns)
            #expect(section(#"Pattern #3 has no "name"; skipped"#) == .patterns)
            #expect(section(#""appearance" "sepia" isn't "system", "light" or "dark"; following the system"#) == .appearance)
            #expect(section(#""theme" is ignored: the JSON Viewer uses GitHub Light and Dark; "appearance" picks light or dark"#) == .appearance)
            #expect(section(#""inspectorLayout" "grid" isn't "tabs" or "list"; using "tabs""#) == .general)
            #expect(section("Config file isn't valid JSON (line 2)") == .general)
            #expect(section("Grok Definition A: grok definitions loop: A → B → A; skipped") == .grokDefinitions)
            #expect(section(#""grok" [] isn't like { "NAME": "regex" }; ignored"#) == .grokDefinitions)
        }
    }
}
