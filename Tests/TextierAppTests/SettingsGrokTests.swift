import AppKit
import Testing
import TextierCore
@testable import Textier

extension AppTests {
    @MainActor
    @Suite("Settings: Grok Definitions")
    struct SettingsGrokTests {
        static let accessLine = #"203.0.113.7 - - [09/Oct/2026:10:15:32 +0700] "GET /api/v1/signin HTTP/1.1" 200 512"#

        func fileGrok(_ app: AppHarness) throws -> [GrokDefinition] {
            try #require(ConfigFile.load(Data(app.configText.utf8)).config).grok
        }

        @Test func theBundledDefinitionsAreListedWithTheirRegex() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.bundledGrok == GrokDefinition.bundled)
                #expect(settings.bundledGrok.contains { $0.name == "IPV4" && $0.regex.hasPrefix("(?<![0-9])") })
                settings.grokFilter = "iso8601"
                #expect(settings.visibleBundledGrok.map(\.name) == ["ISO8601_TIMEZONE", "ISO8601_SECOND", "TIMESTAMP_ISO8601"])
            }
        }

        @Test func addingADefinitionWritesItAndPatternsCanUseIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.addGrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#) == nil)
                #expect(try fileGrok(app) == [GrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#)])

                settings.addPattern()
                let index = try #require(settings.selectedPattern)
                settings.setPatternRegex("%{MYTICKET}", at: index)
                app.capture("fix ABC-12 today")
                #expect(app.inspection.tab(.pattern("new pattern"))?.entries.map(\.text) == ["ABC-12"])
            }
        }

        @Test func aBadNameOrRegexIsReportedAndNotWritten() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.addGrokDefinition(name: "MY TICKET", regex: "x")?.contains("letters, digits and _") == true)
                #expect(settings.addGrokDefinition(name: "LOOP", regex: "a%{LOOP}") == "grok definitions loop: LOOP → LOOP")
                #expect(try fileGrok(app).isEmpty)
            }
        }

        @Test func editingADefinitionThatWouldLoopKeepsADraftAndIsntWritten() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.addGrokDefinition(name: "A", regex: "a") == nil)
                #expect(settings.addGrokDefinition(name: "B", regex: "b%{A}") == nil)

                settings.setGrokRegex("a%{B}", named: "A")
                #expect(settings.draft(.grokRegex("A"))?.problem == "grok definitions loop: A → B → A")
                #expect(try fileGrok(app).first == GrokDefinition(name: "A", regex: "a"))
                settings.setGrokRegex("aa", named: "A")
                #expect(settings.draft(.grokRegex("A")) == nil)
                #expect(try fileGrok(app).first == GrokDefinition(name: "A", regex: "aa"))
            }
        }

        @Test func pastingNameRegexLinesAddsEachAndReportsTheRest() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                let problems = settings.pasteGrokDefinitions("""
                # From Logstash
                MYHOST [a-z]+\\.internal
                MYPORT \\d{2,5}

                MYADDR %{MYHOST}:%{MYPORT}
                just-one-word
                """)
                #expect(try fileGrok(app).map(\.name) == ["MYHOST", "MYPORT", "MYADDR"])
                #expect(problems == [#"Line 6: "just-one-word" isn't NAME regex"#])
            }
        }

        @Test func pastedLinesCanEndInCRLF() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.pasteGrokDefinitions("A_ID [A-Z]+\r\nB_LVL (INFO|WARN)\r\n\r\njust-one-word").count == 1)
                #expect(try fileGrok(app) == [
                    GrokDefinition(name: "A_ID", regex: "[A-Z]+"),
                    GrokDefinition(name: "B_LVL", regex: "(INFO|WARN)"),
                ])
                #expect(settings.pasteGrokDefinitions("C_X x\r\nnot-a-name x") == [#"Line 2: "not-a-name x" isn't NAME regex"#])
            }
        }

        @Test func aUserDefinitionWithABundledNameIsMarkedAsOverridingIt() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()

                #expect(settings.addGrokDefinition(name: "LOGLEVEL", regex: "(?:WARN|ERR)") == nil)
                #expect(settings.overridesBundled("LOGLEVEL"))
                #expect(!settings.overridesBundled("MYTICKET"))
            }
        }

        @Test func aDefinitionAPatternUsesCantBeDeleted() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                #expect(settings.addGrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#) == nil)
                #expect(settings.addGrokDefinition(name: "SPARE", regex: "x") == nil)
                settings.addPattern()
                settings.setPatternRegex("%{MYTICKET}", at: try #require(settings.selectedPattern))

                #expect(settings.deleteGrokDefinition(named: "MYTICKET") == #"Pattern "new pattern" uses it"#)
                #expect(settings.deleteGrokDefinition(named: "SPARE") == nil)
                #expect(try fileGrok(app).map(\.name) == ["MYTICKET"])
            }
        }

        @Test func newPatternFromADefinitionAddsItAndOpensItInTheEditor() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.section = .grokDefinitions

                settings.newPattern(fromGrok: "TIMESTAMP_ISO8601")
                let index = try #require(settings.selectedPattern)
                let pattern = settings.config.patterns[index]
                #expect(pattern.name == "timestamp iso8601")
                #expect(pattern.kind == .regex("%{TIMESTAMP_ISO8601}"))
                #expect(pattern.actions == [.copy])
                #expect(settings.section == .patterns)
            }
        }

        @Test func aPatternFromADefinitionThatCantBeAddedOpensNothing() async throws {
            try await runInApp {
                let app = try AppHarness(config: #"{ "patterns": [], "grok": { "IPV4": "(" } }"#)
                defer { app.tearDown() }
                let settings = try app.openSettings()
                settings.section = .grokDefinitions
                let before = app.configText

                // The file's broken IPV4 would get the Pattern skipped on load.
                settings.newPattern(fromGrok: "IPV4")
                #expect(settings.selectedPattern == nil)
                #expect(settings.section == .grokDefinitions)
                #expect(settings.sectionMessages.contains { $0.hasPrefix("Couldn't add a Pattern for IPV4") })
                #expect(app.configText == before)

                // A file that can't be read isn't written over.
                try app.writeConfig("{")
                settings.newPattern(fromGrok: "WORD")
                #expect(settings.selectedPattern == nil)
                #expect(settings.config.patterns.isEmpty)
            }
        }

        /// The spec's done scenario.
        @Test func buildingTheNginxAccessPatternInSettingsShowsItsFieldsInTheTestBoxThenThePanel() async throws {
            try await runInApp {
                let app = try AppHarness()
                defer { app.tearDown() }
                app.capture(Self.accessLine)
                let settings = try app.openSettings()

                settings.section = .patterns
                settings.addPattern()
                let index = try #require(settings.selectedPattern)
                settings.setPatternName("access", at: index)
                settings.editedRegex = #"%{IPV4:client} - - \[%{HTTPDATE:time}\] "%{WORD:method} %{URIPATHPARAM:path}"#
                let match = try #require(try settings.testMatches.get().first)
                settings.selectTestMatch(at: match.range.location)
                #expect(settings.selectedTestFields.map(\.label) == ["client", "time", "method", "path"])

                settings.commitEditedRegex()
                try app.select("access", 0)
                let fields = try #require(app.model.selectedEntry?.fields)
                #expect(fields.map(\.field.label) == ["client", "time", "method", "path"])
                fields[0].copy()
                #expect(app.copied == "203.0.113.7")
            }
        }
    }
}
