import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Settings: Patterns")
    struct SettingsPatternTests {
        func index(of name: String, in settings: SettingsModel) throws -> Int {
            try #require(settings.config.patterns.firstIndex { $0.name == name })
        }

        /// The Pattern names in the config file, in order.
        func fileNames(_ app: AppHarness) throws -> [String] {
            try #require(ConfigFile.load(Data(app.configText.utf8)).config).patterns.map(\.name)
        }

        @Test func everySectionShows() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                let settings = try app.openSettings()
                let window = try #require(app.settingsWindow).window

                for section in SettingsModel.Section.allCases {
                    settings.section = section
                    settings.selectedPattern = section == .patterns ? 2 : nil
                    app.spin(0.2)
                    window.contentView?.layoutSubtreeIfNeeded()
                }
                #expect(window.isVisible)
            }
        }

        // MARK: The list

        @Test func everyPatternIsListedInPriorityOrderAndTheFilterNarrowsIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.visiblePatterns == Array(Config.default.patterns.indices))
                settings.patternFilter = "PATH"
                #expect(settings.visiblePatterns.map { settings.config.patterns[$0].name } == ["file path"])
                // The regex counts too.
                settings.patternFilter = "https?"
                #expect(settings.visiblePatterns.map { settings.config.patterns[$0].name } == ["url"])
            }
        }

        @Test func draggingAPatternWritesTheNewOrderAndChangesWhichWinsAnOverlap() async throws {
            try await runInApp {
                let narrow = Pattern(name: "pair", regex: #"\d+-\d+"#, actions: [.copy])
                let wide = Pattern(name: "key", regex: #"[A-Z]+-\d+"#, actions: [.copy])
                let app = try AppHarness()
                defer { app.tearDown() }
                try app.writeConfig(Config(patterns: Config.default.patterns + [narrow, wide]))
                app.capture("AB-12-34")
                #expect(app.tabTitles.first == "pair")
                let settings = try app.openSettings()

                let logLevel = try index(of: "log level", in: settings)
                settings.movePatterns(from: [logLevel], to: try index(of: "url", in: settings))
                #expect(try fileNames(app) == ["json", "escaped-json", "log level", "url", "datetime", "file path", "pair", "key"])

                settings.movePatterns(from: [try index(of: "key", in: settings)], to: try index(of: "pair", in: settings))
                #expect(try fileNames(app).suffix(2) == ["key", "pair"])
                #expect(app.tabTitles.first == "key")
            }
        }

        @Test func turningLogLevelOnWritesItAndThePanelHighlightsLevels() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(AppFixtures.monologLine)
                #expect(!app.tabTitles.contains("log level"))
                let settings = try app.openSettings()

                settings.setPatternEnabled(true, at: try index(of: "log level", in: settings))
                #expect(try #require(ConfigFile.load(Data(app.configText.utf8)).config).patterns.last?.enabled == true)
                #expect(app.tabTitles.contains("log level"))
            }
        }

        // MARK: The editor

        @Test func anInvalidRegexIsADraftNamingTheProblemAndFixingItWrites() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let before = app.configText
                let url = try index(of: "url", in: settings)

                settings.setPatternRegex(#"a\Kb"#, at: url)
                #expect(settings.draft(.patternRegex(url))?.problem == #"\K isn't supported"#)
                #expect(settings.regexText(at: url) == #"a\Kb"#)
                #expect(app.configText == before)

                settings.setPatternRegex(#"https?://\S+"#, at: url)
                #expect(settings.draft(.patternRegex(url)) == nil)
                #expect(app.configText.contains(#""regex": "https?://\\S+""#))
            }
        }

        @Test func aNameIsNeededAndTheBuiltinNamesAreTaken() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)

                settings.setPatternName("", at: url)
                #expect(settings.draft(.patternName(url))?.problem == "A Pattern needs a name")
                settings.setPatternName("json", at: url)
                #expect(settings.draft(.patternName(url))?.problem.contains("reserved") == true)
                settings.setPatternName("link", at: url)
                #expect(settings.draft(.patternName(url)) == nil)
                #expect(try fileNames(app).contains("link"))
            }
        }

        @Test func actionsAndColorAreEditable() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)

                settings.setPatternAction(.openURL, on: false, at: url)
                settings.setPatternAction(.open, on: true, at: url)
                #expect(settings.config.patterns[url].actions == [.copy, .open])
                settings.setPatternColor(PatternColor(light: "#112233", dark: "#445566"), at: url)
                #expect(app.configText.contains(##""color": { "light": "#112233", "dark": "#445566" }"##))
                #expect(settings.color(ofPatternAt: url) == PatternColor(light: "#112233", dark: "#445566"))
            }
        }

        @Test func deletingTheLastPatternWhileItsEditorShowsDoesntCrash() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.section = .patterns
                app.spin(0.2)

                // The editor shows the new, last Pattern; the minus button deletes it.
                settings.addPattern()
                let added = try #require(settings.selectedPattern)
                app.spin(0.3)
                settings.deletePattern(at: added)
                app.spin(0.3)
                #expect(settings.selectedPattern == nil)
                #expect(settings.config.patterns.count == added)
                try #require(app.settingsWindow).window.layoutIfNeeded()
                try #require(app.settingsWindow).window.displayIfNeeded()
            }
        }

        @Test func addDeleteAndDuplicateChangeTheFile() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                settings.addPattern()
                let added = try #require(settings.selectedPattern)
                #expect(settings.kind(ofPatternAt: added) == .user)
                #expect(try fileNames(app).last == "new pattern")
                settings.deletePattern(at: added)
                #expect(try fileNames(app) == Config.default.patterns.map(\.name))

                let url = try index(of: "url", in: settings)
                settings.duplicatePattern(at: url)
                let copy = try #require(settings.selectedPattern)
                #expect(copy == url + 1)
                #expect(settings.config.patterns[copy].name == "url copy")
                #expect(settings.config.patterns[copy].kind == Preset.url.kind)
                #expect(settings.kind(ofPatternAt: copy) == .user)
                #expect(try fileNames(app)[copy] == "url copy")
            }
        }

        @Test func presetsCantBeDeletedButCanBeRestoredOnceChanged() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)

                #expect(settings.kind(ofPatternAt: url) == .preset)
                settings.deletePattern(at: url)
                #expect(try fileNames(app).contains("url"))
                #expect(!settings.canRestoreDefault(at: url))

                settings.setPatternRegex(#"https://\S+"#, at: url)
                settings.setPatternAction(.open, on: true, at: url)
                // Turning it off isn't a change from its default.
                settings.setPatternEnabled(false, at: url)
                #expect(settings.canRestoreDefault(at: url))
                settings.restoreDefault(at: url)
                var restored = Preset.url
                restored.enabled = false
                #expect(settings.config.patterns[url] == restored)
                #expect(!settings.canRestoreDefault(at: url))
            }
        }

        @Test func builtinPatternsOnlyTurnOnAndOff() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let json = try index(of: "json", in: settings)
                let before = app.configText

                #expect(settings.kind(ofPatternAt: json) == .builtin)
                settings.setPatternName("blob", at: json)
                settings.setPatternRegex("x", at: json)
                settings.duplicatePattern(at: json)
                settings.deletePattern(at: json)
                #expect(app.configText == before)
                settings.setPatternEnabled(false, at: json)
                #expect(settings.config.patterns[json].enabled == false)
            }
        }

        @Test func patternsThatShareANameShowTheSameColor() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                try app.writeConfig(Config(patterns: [
                    Pattern(name: "numeric", regex: #"\b\d+\.\d+\b"#, actions: [.copy], color: "#112233"),
                    Pattern(name: "numeric", regex: #"\b\d+\b"#, actions: [.copy], color: "#445566"),
                ]))
                let settings = try app.openSettings()

                #expect(settings.color(ofPatternAt: 0) == "#112233")
                #expect(settings.color(ofPatternAt: 1) == "#112233")
            }
        }

        @Test func aPatternTheFileCouldntLoadSurvivesASettingsWrite() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [
                  { "name": "being fixed", "regex": "(unclosed", "actions": ["copy"] },
                  { "name": "url", "regex": "https?://\\S+", "actions": ["open-url", "copy"] }
                ] }
                """#)
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.warnings(in: .patterns).count == 1)

                settings.setCopyJSON(.pretty)
                #expect(app.configText.contains(#""regex": "(unclosed""#))
                #expect(settings.warnings(in: .patterns).count == 1)
            }
        }

        @Test func anInvalidDraftFollowsItsPatternWhenTheListIsReordered() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)

                settings.setPatternRegex("(", at: url)
                settings.movePatterns(from: [url], to: 0)
                #expect(settings.config.patterns[0].name == "url")
                #expect(settings.draft(.patternRegex(0))?.text == "(")
                #expect(settings.draft(.patternRegex(url)) == nil)
            }
        }

        // MARK: The regex being typed

        /// A click on a button doesn't take the focus, so the field's leaving never
        /// saves it; the buttons that open another Pattern do.
        @Test func aRegexBeingTypedIsSavedBeforeAnotherPatternOpens() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)
                settings.selectedPattern = url

                settings.editedRegex = #"https://\S+"#
                settings.duplicatePattern(at: url)
                #expect(settings.selectedPattern == url + 1)
                #expect(settings.config.patterns[url].kind == .regex(#"https://\S+"#))
                #expect(settings.config.patterns[url + 1].kind == .regex(#"https://\S+"#))

                settings.editedRegex = #"ftp://\S+"#
                settings.addPattern()
                #expect(settings.config.patterns[url + 1].kind == .regex(#"ftp://\S+"#))
                #expect(settings.selectedPattern == settings.config.patterns.count - 1)
            }
        }

        @Test func restoringADefaultDropsTheRegexBeingTyped() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)
                settings.selectedPattern = url
                settings.setPatternRegex(#"https://\S+"#, at: url)

                settings.editedRegex = #"ftp://\S+"#
                settings.restoreDefault(at: url)
                #expect(settings.editedRegex == nil)
                settings.commitEditedRegex()
                #expect(settings.config.patterns[url].kind == Preset.url.kind)
            }
        }

        @Test func anEditTheFileCantTakeStaysAsADraftUntilItCan() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let url = try index(of: "url", in: settings)
                settings.selectedPattern = url
                try app.writeConfig("{")

                settings.editedRegex = #"https://\S+"#
                settings.commitEditedRegex()
                let draft = try #require(settings.draft(.patternRegex(url)))
                #expect(draft.problem.hasPrefix("Settings won't overwrite the config file"))
                #expect(settings.regexText(at: url) == #"https://\S+"#)
                settings.setPatternName("links", at: url)
                #expect(settings.nameText(at: url) == "links")
                #expect(app.configText == "{")

                try app.writeConfig(Config.default)
                settings.setPatternRegex(settings.regexText(at: url), at: url)
                #expect(settings.draft(.patternRegex(url)) == nil)
                #expect(settings.config.patterns[url].regex == #"https://\S+"#)
            }
        }
    }
}
