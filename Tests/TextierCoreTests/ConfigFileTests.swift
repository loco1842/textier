import Foundation
import Testing
import TextierCore

@Suite("Config file")
struct ConfigFileTests {
    /// A config as a user would leave it after a few edits: the shipped Built-in and
    /// Presets, a User Pattern for PHP class names with a color, a custom shortcut
    /// and an editor command.
    let edited = #"""
    {
      "shortcut": "cmd+shift+space",
      "editorCommand": "zed {path}:{line}",
      "patterns": [
        { "name": "json", "builtin": "json", "enabled": true, "actions": ["open", "copy-pretty", "copy"] },
        { "name": "url", "regex": "\\bhttps?://[^\\s\"'`)\\]}>]*[^\\s\"'`)\\]}>.,;:!?]", "enabled": true, "actions": ["open-url", "copy"] },
        {
          "name": "php class",
          "regex": "\\b(?:[A-Z]\\w*\\\\{1,2})+[A-Z]\\w*\\b",
          "actions": ["copy"],
          "color": "#c678dd"
        }
      ]
    }
    """#

    func load(_ text: String) -> ConfigLoad {
        ConfigFile.load(Data(text.utf8))
    }

    /// A shipped Pattern as a v1 config file lists it: no `color`.
    func withoutColor(_ pattern: Pattern) -> Pattern {
        var pattern = pattern
        pattern.color = nil
        return pattern
    }

    // MARK: Default emission

    @Test func defaultEmissionLoadsBackIdenticallyWithNoWarnings() {
        let loaded = ConfigFile.load(ConfigFile.encode(.default))

        #expect(loaded.config == .default)
        #expect(loaded.warnings.isEmpty)
    }

    @Test func emittedStringsEscapeQuotesBackslashesAndControlCharactersButNotSlashes() throws {
        let tricky = Pattern(name: "say \"hi\"\tC:\\ \u{1}", regex: #"https?://\S+"#, actions: [.copy])
        let config = Config(patterns: [tricky], editorCommand: "zed {path}:{line}")
        let data = ConfigFile.encode(config)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(#""name": "say \"hi\"\tC:\\ \u0001""#))
        #expect(text.contains(#""regex": "https?://\\S+""#))
        #expect(ConfigFile.load(data).config == config)
    }

    @Test func defaultEmissionDocumentsEveryPatternShortcutAndEmptyEditorCommand() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))

        #expect(!text.contains("copyJSON"))
        #expect(text.contains(#""appearance": "system""#))
        #expect(!text.contains(#""theme""#))
        #expect(text.contains(##""color": "#"##) || text.contains(##""color": { "light""##))
        #expect(text.contains(#""shortcut": "ctrl+option+t""#))
        #expect(text.contains(#""editorCommand": """#))
        #expect(text.contains(#""builtin": "json""#))
        for name in ["json", "url", "datetime", "file path", "log level"] {
            #expect(text.contains(#""name": "\#(name)""#))
        }
    }

    @Test func emittedEntriesKeepADocumentedKeyOrder() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        let url = try #require(text.range(of: #""name": "url""#))
        let rest = text[url.lowerBound...]
        let keys = [#""name""#, #""regex""#, #""enabled""#, #""actions""#]
        let offsets = try keys.map { try #require(rest.range(of: $0)).lowerBound }

        #expect(offsets == offsets.sorted())
    }

    @Test func emittedRegexKeepsForwardSlashesReadable() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))

        #expect(text.contains("https?://"))
    }

    @Test func colorAndEditorCommandRoundTrip() {
        var config = Config.default
        config.patterns[1].color = "#ff8800"
        config.editorCommand = "code -g {path}:{line}"
        config.shortcut = Shortcut("cmd+shift+space")!

        #expect(ConfigFile.load(ConfigFile.encode(config)).config == config)
    }

    // MARK: Loading

    @Test func loadsAUserEditedFile() throws {
        let loaded = load(edited)
        let config = try #require(loaded.config)

        #expect(loaded.warnings.isEmpty)
        #expect(config.shortcut == Shortcut("cmd+shift+space"))
        #expect(config.editorCommand == "zed {path}:{line}")
        #expect(config.patterns.map(\.name) == ["json", "url", "php class"])
        #expect(config.patterns[0] == withoutColor(Builtin.json))
        #expect(config.patterns[1] == withoutColor(Preset.url))
        #expect(config.patterns[2] == Pattern(
            name: "php class", regex: #"\b(?:[A-Z]\w*\\{1,2})+[A-Z]\w*\b"#, actions: [.copy], color: "#c678dd"
        ))
    }

    @Test func aLoadedUserPatternHighlightsTheMonologRepositoryClass() throws {
        let config = try #require(load(edited).config)
        let texts = detect(Fixtures.monologLine, config: Config(patterns: [config.patterns[2]])).map(\.text)

        #expect(texts == [#"Modules\\Notification\\Repositories\\EmailTemplateRepository"#, #"Illuminate\\Events"#])
    }

    @Test func missingShortcutAndEditorCommandFallBackToDefaults() throws {
        let config = try #require(load(#"{ "patterns": [] }"#).config)

        #expect(config.shortcut == .default)
        #expect(config.editorCommand == nil)
        #expect(config.patterns.isEmpty)
    }

    @Test func emptyEditorCommandMeansUnset() throws {
        #expect(try #require(load(#"{ "editorCommand": "", "patterns": [] }"#).config).editorCommand == nil)
    }

    @Test func disablingJSONLoadsItDisabled() throws {
        let text = #"{ "patterns": [{ "name": "json", "builtin": "json", "enabled": false, "actions": ["open"] }] }"#

        #expect(try #require(load(text).config).patterns.map(\.enabled) == [false])
    }

    // MARK: Skipped Patterns

    @Test func invalidRegexSkipsOnlyThatPatternWithAWarningNamingIt() throws {
        let text = #"""
        { "patterns": [
          { "name": "broken", "regex": "(unclosed", "actions": ["copy"] },
          { "name": "ticket", "regex": "\\b[A-Z]+-\\d+\\b", "actions": ["copy"] }
        ] }
        """#
        let loaded = load(text)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["ticket"])
        let warning = try #require(loaded.warnings.first)
        #expect(loaded.warnings.count == 1)
        #expect(!warning.isFatal)
        #expect(warning.message.contains("broken"))
        #expect(warning.message.contains("unbalanced parenthesis"))
    }

    @Test func aRegexICUCantRunIsSkippedWithAWarningNamingTheConstruct() throws {
        let loaded = load(#"""
        { "patterns": [
          { "name": "kept", "regex": "a\\Kb", "actions": ["copy"] },
          { "name": "ticket", "regex": "(?P<key>[A-Z]+)-\\d+", "actions": ["copy"] }
        ] }
        """#)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["ticket"])
        #expect(loaded.warnings.map(\.message) == [#"Pattern "kept": \K isn't supported; skipped"#])
    }

    @Test func unknownActionSkipsThatPatternWithAWarningNamingTheAction() throws {
        let text = #"""
        { "patterns": [
          { "name": "url", "regex": "https?://\\S+", "actions": ["open-url", "opne"] },
          { "name": "datetime", "regex": "\\d{4}-\\d{2}-\\d{2}", "actions": ["copy"] }
        ] }
        """#
        let loaded = load(text)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["datetime"])
        let warning = try #require(loaded.warnings.first)
        #expect(loaded.warnings.count == 1)
        #expect(warning.message.contains("url"))
        #expect(warning.message.contains("opne"))
    }

    @Test func unknownBuiltinSkipsThatPatternWithAWarning() throws {
        let text = #"{ "patterns": [{ "name": "yaml", "builtin": "yaml", "actions": ["open"] }] }"#
        let loaded = load(text)

        #expect(try #require(loaded.config).patterns.isEmpty)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.message.contains("yaml") == true)
    }

    @Test(arguments: [
        #"{ "name": "json", "regex": "\\{.*\\}", "actions": ["copy"] }"#,
        #"{ "name": "escaped-json", "regex": "x", "actions": ["copy"] }"#,
        #"{ "name": "json", "builtin": "escaped-json", "actions": ["open"] }"#,
    ])
    func aPatternTakingABuiltinsNameIsSkippedWithAWarningNamingTheReservedName(entry: String) throws {
        let loaded = load(#"{ "patterns": [\#(entry), { "name": "ok", "regex": "x", "actions": ["copy"] }] }"#)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["ok"])
        let warning = try #require(loaded.warnings.first)
        #expect(loaded.warnings.count == 1)
        #expect(warning.message.contains("reserved"))
    }

    @Test func patternsCanShareAName() throws {
        let loaded = load(#"""
        { "patterns": [
          { "name": "numeric", "regex": "\\b\\d+\\.\\d+\\b", "actions": ["copy"] },
          { "name": "numeric", "regex": "\\b\\d+\\b", "actions": ["copy", "open"] }
        ] }
        """#)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["numeric", "numeric"])
        #expect(loaded.warnings.isEmpty)
    }

    @Test(arguments: [
        #"{ "regex": "x", "actions": ["copy"] }"#,
        #"{ "name": "both", "regex": "x", "builtin": "json", "actions": ["copy"] }"#,
        #"{ "name": "neither", "actions": ["copy"] }"#,
        #"{ "name": "no actions", "regex": "x" }"#,
        #"{ "name": "flag", "regex": "x", "enabled": "yes", "actions": ["copy"] }"#,
        #""just a string""#,
    ])
    func malformedEntrySkipsWithAWarning(entry: String) throws {
        let loaded = load(#"{ "patterns": [\#(entry), { "name": "ok", "regex": "x", "actions": ["copy"] }] }"#)

        #expect(try #require(loaded.config).patterns.map(\.name) == ["ok"])
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.allSatisfy { !$0.isFatal })
    }

    // MARK: Colors

    @Test(arguments: ["#c678dd", "#C678DD", "#61afef80", "#61AFEF80"])
    func hexColorsLoad(color: String) throws {
        let loaded = load(#"{ "patterns": [{ "name": "ticket", "regex": "x", "actions": ["copy"], "color": "\#(color)" }] }"#)

        #expect(try #require(loaded.config).patterns.first?.color == PatternColor(color))
        #expect(loaded.warnings.isEmpty)
    }

    @Test func aLightDarkPairLoads() throws {
        let loaded = load(##"""
        { "patterns": [{ "name": "ticket", "regex": "x", "actions": ["copy"],
                         "color": { "light": "#9a6700", "dark": "#E3B341" } }] }
        """##)

        #expect(try #require(loaded.config).patterns.first?.color == PatternColor(light: "#9a6700", dark: "#E3B341"))
        #expect(loaded.warnings.isEmpty)
    }

    @Test func singleAndPairedColorsRoundTrip() {
        var config = Config.default
        config.patterns[2].color = "#e5c07b"
        config.patterns[3].color = PatternColor(light: "#9a6700", dark: "#e3b341")
        let data = ConfigFile.encode(config)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains(##""color": "#e5c07b""##))
        #expect(text.contains(##""color": { "light": "#9a6700", "dark": "#e3b341" }"##))
        #expect(ConfigFile.load(data) == ConfigLoad(config: config, warnings: []))
    }

    @Test func aV1FileWithoutColorsGetsThePaletteWithNoWarnings() throws {
        let v1 = #"""
        {
          "shortcut": "ctrl+option+t",
          "editorCommand": "",
          "patterns": [
            { "name": "json", "builtin": "json", "enabled": true, "actions": ["open", "copy-pretty", "copy"] },
            { "name": "escaped-json", "builtin": "escaped-json", "enabled": true, "actions": ["open"] },
            { "name": "url", "regex": "\\bhttps?://[^\\s\"'`)\\]}>]+", "enabled": true, "actions": ["open-url", "copy"] },
            { "name": "file path", "regex": "/\\S+", "enabled": true, "actions": ["open-file", "copy"] },
            { "name": "ticket", "regex": "JIRA-\\d+", "actions": ["copy"] }
          ]
        }
        """#
        let loaded = load(v1)
        let config = try #require(loaded.config)

        #expect(loaded.warnings.isEmpty)
        #expect(config.patterns.allSatisfy { $0.color == nil })
        #expect(config.resolvedColors == [
            Palette.byName["json"], Palette.byName["escaped-json"], Palette.byName["url"],
            Palette.byName["file path"], Palette.forUserPatterns[0],
        ])
        #expect(config.color(of: config.patterns[2]) == Config.default.color(of: Preset.url))
    }

    @Test(arguments: [
        #""orange""#, ##""#abc""##, #""c678dd""#, ##""#c678dz""##, ##""#c678dd8""##, "7",
        ##"{ "light": "#9a6700" }"##, ##"{ "light": "#9a6700", "dark": "blue" }"##, ##"{ "light": 1, "dark": "#e3b341" }"##,
        "[]",
    ])
    func anInvalidColorWarnsNamingThePatternAndLoadsItWithoutAColor(color: String) throws {
        let loaded = load(#"{ "patterns": [{ "name": "ticket", "regex": "x", "actions": ["copy"], "color": \#(color) }] }"#)

        let pattern = try #require(loaded.config?.patterns.first)
        #expect(pattern.name == "ticket")
        #expect(pattern.color == nil)
        let warning = try #require(loaded.warnings.first)
        #expect(loaded.warnings.count == 1)
        #expect(!warning.isFatal)
        #expect(warning.message.contains("ticket"))
        #expect(warning.message.contains("color"))
    }

    // MARK: copyJSON

    /// What a double-click on JSON copied; clicks are a text view's now.
    @Test(arguments: [#""pretty""#, #""raw""#, "1"])
    func copyJSONIsIgnoredWithAWarning(value: String) throws {
        let loaded = load(#"{ "copyJSON": \#(value), "patterns": [] }"#)
        #expect(loaded.config != nil)
        #expect(loaded.warnings.map(\.message) == [#""copyJSON" is ignored: ⌘-click a Match, then Copy or Copy Beautified"#])
        #expect(loaded.warnings.first?.isFatal == false)
    }

    // MARK: inspectorLayout

    @Test func inspectorLayoutDefaultsToTabsAndIsWrittenOnFirstLaunch() throws {
        #expect(try #require(load(#"{ "patterns": [] }"#).config).inspectorLayout == .tabs)
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        #expect(text.contains(#""inspectorLayout": "tabs""#))
    }

    @Test(arguments: [("tabs", InspectorLayout.tabs), ("list", .list)])
    func inspectorLayoutLoadsAndRoundTrips(raw: String, expected: InspectorLayout) throws {
        let loaded = load(#"{ "inspectorLayout": "\#(raw)", "patterns": [] }"#)

        let config = try #require(loaded.config)
        #expect(config.inspectorLayout == expected)
        #expect(loaded.warnings.isEmpty)
        #expect(ConfigFile.load(ConfigFile.encode(config)).config == config)
    }

    @Test(arguments: [#""sections""#, "1", #""List""#])
    func anUnknownInspectorLayoutWarnsAndFallsBackToTabs(value: String) throws {
        let loaded = load(#"{ "inspectorLayout": \#(value), "patterns": [] }"#)

        #expect(try #require(loaded.config).inspectorLayout == .tabs)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.isFatal == false)
        #expect(loaded.warnings.first?.message.contains("inspectorLayout") == true)
    }

    // MARK: appearance

    @Test func appearanceDefaultsToSystem() throws {
        #expect(try #require(load(#"{ "patterns": [] }"#).config).appearance == .system)
    }

    @Test(arguments: [AppearanceSetting.system, .light, .dark])
    func appearanceLoadsAsWrittenAndRoundTrips(appearance: AppearanceSetting) throws {
        let loaded = load(#"{ "appearance": "\#(appearance.rawValue)", "patterns": [] }"#)
        #expect(try #require(loaded.config).appearance == appearance)
        #expect(loaded.warnings.isEmpty)

        var config = Config.default
        config.appearance = appearance
        config.clearSelectionAfter = 30
        #expect(ConfigFile.load(ConfigFile.encode(config)) == ConfigLoad(config: config, warnings: []))
    }

    @Test(arguments: [#""sepia""#, "true", "[]"])
    func anUnknownAppearanceWarnsAndFollowsTheSystem(value: String) throws {
        let loaded = load(#"{ "appearance": \#(value), "patterns": [] }"#)

        #expect(try #require(loaded.config).appearance == .system)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.message.hasPrefix(#""appearance""#) == true)
    }

    // MARK: clearSelectionAfter

    @Test func clearSelectionAfterDefaultsToNeverAndIsWrittenOnFirstLaunch() throws {
        #expect(try #require(load(#"{ "patterns": [] }"#).config).clearSelectionAfter == 0)
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        #expect(text.contains(#""clearSelectionAfter": 0"#))
    }

    @Test(arguments: [0, 30, 300])
    func clearSelectionAfterLoadsAndRoundTrips(seconds: Int) throws {
        let loaded = load(#"{ "clearSelectionAfter": \#(seconds), "patterns": [] }"#)
        #expect(try #require(loaded.config).clearSelectionAfter == seconds)
        #expect(loaded.warnings.isEmpty)

        var config = Config.default
        config.clearSelectionAfter = seconds
        #expect(ConfigFile.load(ConfigFile.encode(config)) == ConfigLoad(config: config, warnings: []))
    }

    @Test(arguments: ["-5", "1.5", #""60""#, "true"])
    func aClearSelectionAfterThatIsntWholeSecondsWarnsAndKeepsTheSelection(value: String) throws {
        let loaded = load(#"{ "clearSelectionAfter": \#(value), "patterns": [] }"#)

        #expect(try #require(loaded.config).clearSelectionAfter == 0)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.isFatal == false)
        #expect(loaded.warnings.first?.message.hasPrefix(#""clearSelectionAfter""#) == true)
    }

    @Test func aThemeKeyIsIgnoredWithAWarning() throws {
        let loaded = load(#"{ "theme": { "dark": "dark.json" }, "patterns": [] }"#)

        #expect(loaded.config != nil)
        #expect(loaded.warnings.map(\.message) == [
            #""theme" is ignored: the JSON Viewer uses GitHub Light and Dark; "appearance" picks light or dark"#,
        ])
        #expect(loaded.warnings.first?.isFatal == false)
    }

    // MARK: Grok Definitions

    @Test func grokDefinitionsRoundTripInFileOrderAfterThePatterns() throws {
        var config = Config.default
        config.grok = [
            GrokDefinition(name: "MYTICKET", regex: #"[A-Z]+-\d+"#),
            GrokDefinition(name: "LOGLEVEL", regex: "(?:WARN|ERR)"),
        ]
        let data = ConfigFile.encode(config)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(ConfigFile.load(data) == ConfigLoad(config: config, warnings: []))
        #expect(text.contains(#""grok": {"#))
        #expect(text.contains(#""MYTICKET": "[A-Z]+-\\d+""#))
        let patterns = try #require(text.range(of: #""patterns""#))
        let grok = try #require(text.range(of: #""grok""#))
        #expect(patterns.lowerBound < grok.lowerBound)
    }

    @Test func theDefaultFileDocumentsAnEmptyGrokObject() throws {
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        #expect(text.contains(#""grok": {}"#))
    }

    @Test func aPatternUsesTheFilesGrokDefinitions() throws {
        let loaded = load(#"""
        { "patterns": [{ "name": "ticket", "regex": "%{MYTICKET:key}", "actions": ["copy"] }],
          "grok": { "MYTICKET": "[A-Z]+-\\d+" } }
        """#)
        let config = try #require(loaded.config)

        #expect(loaded.warnings.isEmpty)
        #expect(detect("fix ABC-12", config: config).map(\.text) == ["ABC-12"])
    }

    @Test func aBadDefinitionWarnsAndPatternsUsingItAreSkipped() throws {
        let loaded = load(#"""
        { "patterns": [
            { "name": "uses bad", "regex": "x%{BAD}", "actions": ["copy"] },
            { "name": "fine", "regex": "%{GOOD}", "actions": ["copy"] }
          ],
          "grok": { "BAD": "(unclosed", "GOOD": "ok" } }
        """#)
        let config = try #require(loaded.config)

        #expect(config.grok == [GrokDefinition(name: "GOOD", regex: "ok")])
        #expect(config.patterns.map(\.name) == ["fine"])
        #expect(loaded.warnings.map(\.message) == [
            #"Grok Definition BAD: unbalanced parenthesis (at character 9); skipped"#,
            #"Pattern "uses bad": unbalanced parenthesis in %{BAD} (at character 2); skipped"#,
        ])
    }

    @Test func aLoopAndAnUnknownNameAreWarningsNamingThem() throws {
        let loaded = load(#"""
        { "patterns": [{ "name": "typo", "regex": "%{NOPE}", "actions": ["copy"] }],
          "grok": { "A": "a%{B}", "B": "b%{A}" } }
        """#)

        #expect(loaded.warnings.map(\.message) == [
            "Grok Definition A: grok definitions loop: A → B → A; skipped",
            "Grok Definition B: grok definitions loop: B → A → B; skipped",
            #"Pattern "typo": unknown grok definition NOPE; skipped"#,
        ])
    }

    @Test(arguments: [
        (#"[]"#, #""grok""#),
        (#"{ "MY TICKET": "x" }"#, "MY TICKET"),
        (#"{ "TICKET": 7 }"#, "TICKET"),
    ])
    func aMalformedGrokEntryWarnsAndIsIgnored(grok: String, named: String) throws {
        let loaded = load(#"{ "patterns": [], "grok": \#(grok) }"#)

        #expect(try #require(loaded.config).grok.isEmpty)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.message.contains(named) == true)
    }

    // MARK: Entries that didn't load

    @Test func writingBackKeepsTheEntriesThatWereSkippedWhereTheyWere() throws {
        let file = #"""
        { "patterns": [
            { "name": "first", "regex": "a", "actions": ["copy"] },
            { "name": "being fixed", "regex": "(unclosed", "actions": ["copy"] },
            { "name": "last", "regex": "b", "actions": ["copy"] }
          ],
          "grok": { "HALF": "(x", "GOOD": "ok" } }
        """#
        let loaded = load(file)
        var config = try #require(loaded.config)
        #expect(loaded.skipped.patterns.map(\.position) == [1])
        #expect(loaded.skipped.grok.map(\.entry.key) == ["HALF"])

        config.shortcut = Shortcut("cmd+shift+space")!
        let written = ConfigFile.encode(config, keeping: loaded.skipped)
        let reloaded = ConfigFile.load(written)

        #expect(reloaded.config == config)
        #expect(reloaded.warnings == loaded.warnings)
        #expect(reloaded.skipped == loaded.skipped)
        let text = try #require(String(data: written, encoding: .utf8))
        let order = try ["first", "being fixed", "last"].map { try #require(text.range(of: #""\#($0)""#)).lowerBound }
        #expect(order == order.sorted())
    }

    @Test func writingBackKeepsColorRulesThatWereSkippedWhereTheyWere() throws {
        let file = #"""
        { "patterns": [
            { "name": "status", "regex": "\\b[1-5]\\d\\d\\b", "actions": ["copy"], "colors": [
              { "when": "^5", "color": "#e5484d" },
              { "when": "(unclosed", "color": "#ef5f00" },
              { "when": "^2", "color": "#46a758" },
              "not a rule"
            ] },
            { "name": "only broken", "regex": "x", "actions": ["copy"], "colors": [{ "when": "^1", "color": "red" }] }
          ] }
        """#
        let loaded = load(file)
        var config = try #require(loaded.config)
        #expect(config.patterns[0].colorRules?.map(\.when) == ["^5", "^2"])
        #expect(config.patterns[0].skippedColorRules.map(\.position) == [1, 3])
        #expect(config.patterns[1].colorRules == [])
        #expect(loaded.warnings.count == 3)

        // A Settings edit to the Pattern, then the write.
        config.patterns[0].actions = [.copy, .openURL]
        let written = ConfigFile.encode(config, keeping: loaded.skipped)
        let reloaded = ConfigFile.load(written)

        #expect(reloaded.config == config)
        #expect(reloaded.warnings == loaded.warnings)
        let text = try #require(String(data: written, encoding: .utf8))
        let order = try [#""^5""#, #""(unclosed""#, #""^2""#, #""not a rule""#, #""red""#].map {
            try #require(text.range(of: $0)).lowerBound
        }
        #expect(order == order.sorted())
        #expect(text.contains(##"{ "when": "(unclosed", "color": "#ef5f00" }"##))
    }

    // MARK: Former Preset regexes

    /// The url Preset's regex as textier shipped it before it stopped taking a
    /// sentence's trailing punctuation.
    let formerURLRegex = #"\bhttps?://[^\s"'`)\]}>]+"#

    /// A file with one Pattern per `(name, regex)`.
    func file(_ patterns: [(name: String, regex: String)]) -> String {
        let entries = patterns.map { pattern in
            #"{ "name": \#(JSONValue.string(pattern.name).prettyPrinted), "regex": \#(JSONValue.string(pattern.regex).prettyPrinted), "actions": ["open-url", "copy"] }"#
        }
        return #"{ "patterns": [\#(entries.joined(separator: ", "))] }"#
    }

    @Test func aPresetWithAFormerShippedRegexLoadsWithTheCurrentOne() throws {
        #expect(Preset.formerRegexes["url"] == [formerURLRegex])
        let loaded = load(file([("url", formerURLRegex)]))
        let config = try #require(loaded.config)
        #expect(loaded.warnings.isEmpty)
        #expect(config.patterns[0].regex == Preset.url.regex)
    }

    @Test func theLogLevelPresetsUppercaseOnlyRegexLoadsAsTheCaseInsensitiveOne() throws {
        let former = #"\b(?:EMERGENCY|ALERT|CRITICAL|ERROR|WARNING|NOTICE|INFO|DEBUG)\b"#
        let config = try #require(load(file([("log level", former)])).config)
        #expect(config.patterns[0].regex == Preset.logLevel.regex)
    }

    @Test func anEditedPresetRegexAndOtherPatternsWithTheFormerTextAreLeftAlone() throws {
        let edited = formerURLRegex + "/"
        let config = try #require(load(file([
            ("links", formerURLRegex), ("url", edited), ("url", formerURLRegex),
        ])).config)
        // A User Pattern named otherwise, the Preset as edited, and a User Pattern
        // in the Preset's group.
        #expect(config.patterns.map(\.regex) == [formerURLRegex, edited, formerURLRegex])
    }

    @Test func theCurrentRegexIsWhatTheFileGetsOnTheNextWrite() throws {
        let original = file([("url", formerURLRegex)])
        let config = try #require(load(original).config)
        let written = ConfigFile.encode(config)
        let text = try #require(String(data: written, encoding: .utf8))
        #expect(!text.contains(JSONValue.string(formerURLRegex).prettyPrinted))
        #expect(text.contains(JSONValue.string(Preset.url.regex!).prettyPrinted))
        #expect(ConfigFile.load(written).config == config)
    }

    @Test func invalidShortcutWarnsAndKeepsTheDefault() throws {
        let loaded = load(#"{ "shortcut": "hyper+t", "patterns": [] }"#)

        #expect(try #require(loaded.config).shortcut == .default)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.message.contains("hyper+t") == true)
    }

    // MARK: Fatal

    @Test(arguments: [
        #"{ "patterns": [ { "name": "url", } ] "#,
        "",
        "[]",
        #"{ "shortcut": "ctrl+option+t" }"#,
        #"{ "patterns": {} }"#,
    ])
    func malformedFileIsOneFatalWarningAndNoConfig(text: String) throws {
        let loaded = load(text)

        #expect(loaded.config == nil)
        #expect(loaded.warnings.count == 1)
        #expect(loaded.warnings.first?.isFatal == true)
    }

    @Test func malformedFileWarningNamesTheLineWhereTheJSONBreaks() {
        let text = """
        {
          "shortcut": "ctrl+option+t",
          "patterns": [
            { "name": "url", "regex": "x", "actions": ["copy"], }
          ]
        }
        """

        #expect(load(text).warnings.map(\.message) == ["Config file isn't valid JSON (line 4)"])
    }

    @Test func aRepeatedKeyTakesItsLastValue() throws {
        let text = #"{ "patterns": [], "shortcut": "ctrl+option+t", "shortcut": "cmd+shift+k" }"#

        #expect(try #require(load(text).config).shortcut == Shortcut("cmd+shift+k"))
    }

    // MARK: First launch

    @Test func writeDefaultIfAbsentCreatesTheDirectoryAndFileOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("textier-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("textier/config.json")

        #expect(try ConfigFile.writeDefaultIfAbsent(at: file) == true)
        #expect(ConfigFile.load(try Data(contentsOf: file)).config == .default)

        try Data(#"{ "patterns": [] }"#.utf8).write(to: file)
        #expect(try ConfigFile.writeDefaultIfAbsent(at: file) == false)
        #expect(ConfigFile.load(try Data(contentsOf: file)).config?.patterns.isEmpty == true)
    }
}
