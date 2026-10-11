import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Settings: names, broken definitions and outside edits")
    struct SettingsEdgeTests {
        @Test func aUserPatternThatJoinsAPresetsGroupIsStillAUserPattern() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                try app.writeConfig(Config(patterns: Config.default.patterns + [
                    Pattern(name: "url", regex: #"\bftp://\S+"#, actions: [.copy]),
                ]))
                let settings = try app.openSettings()
                let mine = settings.config.patterns.count - 1

                #expect(settings.kind(ofPatternAt: 2) == .preset)
                #expect(settings.kind(ofPatternAt: mine) == .user)
                #expect(!settings.canRestoreDefault(at: mine))
                settings.deletePattern(at: mine)
                #expect(settings.config.patterns.count == Config.default.patterns.count)
            }
        }

        @Test func settingsChecksPatternsAgainstABrokenDefinitionAsLoadingDoes() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"{ "patterns": [{ "name": "url", "regex": "x", "actions": ["copy"] }], "grok": { "IPV4": "(" } }"#)
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.selectedPattern = 0
                let before = app.configText

                settings.setPatternRegex("%{IPV4}", at: 0)
                #expect(settings.draft(.patternRegex(0))?.problem.contains("in %{IPV4}") == true)
                #expect(app.configText == before)
                settings.editedRegex = "%{IP}"
                guard case .failure = settings.testMatches else {
                    Issue.record("expected the broken IPV4 to break IP too")
                    return
                }
            }
        }

        @Test func definitionEditsAndPastesAreCheckedAgainstABrokenDefinitionAsLoadingDoes() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [{ "name": "url", "regex": "x", "actions": ["copy"] }], "grok": { "IPV4": "(", "CLIENT": "x" } }
                """#)
                defer { app.tearDown() }
                let settings = try app.openSettings()
                let before = app.configText

                settings.setGrokRegex("%{IP}", named: "CLIENT")
                #expect(settings.draft(.grokRegex("CLIENT"))?.problem.contains("in %{IP}") == true)
                #expect(app.configText == before)
                let problems = settings.pasteGrokDefinitions("SRC %{IP}")
                #expect(problems.count == 1)
                #expect(problems.first?.hasPrefix("Line 1: SRC: ") == true)
                #expect(app.configText == before)
            }
        }

        @Test func aDefinitionChangeThatWouldBreakAPatternUsingItIsntWritten() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"""
                { "patterns": [{ "name": "pair", "regex": "%{A}\\k<n>", "actions": ["copy"] }], "grok": { "A": "(?<n>b)" } }
                """#)
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.config.patterns.map(\.name) == ["pair"])
                let before = app.configText

                settings.setGrokRegex("b", named: "A")
                #expect(settings.draft(.grokRegex("A"))?.problem.hasPrefix(#"Pattern "pair" uses it"#) == true)
                #expect(app.configText == before)
                let problems = settings.pasteGrokDefinitions("A b")
                #expect(problems.count == 1)
                #expect(problems.first?.hasPrefix(#"Line 1: A: Pattern "pair" uses it"#) == true)
                #expect(app.configText == before)
            }
        }

        @Test func aDraftFollowsItsPatternWhenTheFileIsReorderedFromOutside() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.setPatternRegex("(", at: 2)  // url

                try app.writeConfig(Config(patterns: [Pattern(name: "first", regex: "a", actions: [.copy])] + Config.default.patterns))
                #expect(settings.config.patterns[3].name == "url")
                let draft = try #require(settings.draft(.patternRegex(3)))
                #expect(draft.text == "(")
                #expect(draft.fileChanged)
                #expect(settings.draft(.patternRegex(2)) == nil)
            }
        }

        @Test func pastingABrokenVersionOfADefinitionKeepsTheWorkingOne() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.addGrokDefinition(name: "FOO", regex: "foo") == nil)

                let problems = settings.pasteGrokDefinitions("FOO (bad\nBAR bar")
                #expect(problems.count == 1)
                #expect(settings.config.grok == [GrokDefinition(name: "FOO", regex: "foo"), GrokDefinition(name: "BAR", regex: "bar")])
            }
        }

        @Test func aNewPatternFromADefinitionNeverTakesABuiltinsName() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.addGrokDefinition(name: "JSON", regex: #"\{.*\}"#) == nil)

                settings.newPattern(fromGrok: "JSON")
                let index = try #require(settings.selectedPattern)
                #expect(settings.config.patterns[index].name == "json pattern")
            }
        }
    }
}
