import Foundation
import Testing
import TextierCore

@Suite("Color Rules: a Match's color by its text")
struct ColorRuleTests {
    let red = PatternColor("#e5484d")
    let amber = PatternColor("#ffc53d")
    let line = "[2026-10-07] develop.WARNING: slow; develop.ERROR: failed; develop.DEBUG: retry"

    func load(_ text: String) -> ConfigLoad {
        ConfigFile.load(Data(text.utf8))
    }

    /// The log level Preset, enabled, with `colors` as written (nil leaves it out).
    func config(colors: String?) -> String {
        let rules = colors.map { #", "colors": \#($0)"# } ?? ""
        return #"""
        { "patterns": [{ "name": "log level", "regex": "\\b(?:ERROR|WARNING|DEBUG)\\b", "actions": ["copy"]\#(rules) }] }
        """#
    }

    func colors(_ text: String, _ config: Config) -> [String: PatternColor?] {
        Dictionary(uniqueKeysWithValues: detect(text, config: config).map { ($0.text, $0.color) })
    }

    @Test func theFirstRuleWhoseRegexIsInTheMatchGivesItsColorIgnoringCase() throws {
        let config = try #require(load(config(colors: #"""
            [{ "when": "error|crit", "color": "#e5484d" }, { "when": "^warn", "color": "#ffc53d" }]
            """#)).config)
        let found = colors(line, config)
        #expect(found["ERROR"] == red)
        #expect(found["WARNING"] == amber)
        // No rule: the Pattern's own color.
        #expect(found["DEBUG"] == config.resolvedColors[0])
    }

    @Test func aPresetWithoutColorsTakesItsDefaultRules() throws {
        let config = try #require(load(config(colors: nil)).config)
        #expect(config.patterns[0].colorRules == nil)
        #expect(config.patterns[0].effectiveColorRules == Preset.logLevel.colorRules)
        let found = colors(line, config)
        #expect(found["WARNING"] != found["ERROR"])
        #expect(found["DEBUG"] != found["ERROR"])
    }

    @Test func theLogLevelPresetFindsLevelsInAnyCaseAndColorsThem() {
        var logLevel = Preset.logLevel
        logLevel.enabled = true
        let found = colors("error: x; Warning: y; info: z; DEBUG: w", Config(patterns: [logLevel]))
        #expect(found.keys.sorted() == ["DEBUG", "Warning", "error", "info"])
        #expect(found["error"] == red)
        #expect(found["Warning"] == PatternColor("#ffe629"))
        #expect(found["info"] == PatternColor("#0090ff"))
    }

    @Test func anEmptyListTurnsThemOff() throws {
        let config = try #require(load(config(colors: "[]")).config)
        #expect(config.patterns[0].effectiveColorRules == [])
        let found = colors(line, config)
        #expect(Set(found.values.map { $0?.light }).count == 1)
    }

    @Test func aBadRuleIsSkippedWithAWarningAndTheRestKept() {
        let loaded = load(config(colors: #"""
            [{ "when": "(", "color": "#e5484d" }, { "when": "warn", "color": "red" }, { "when": "debug", "color": "#8d8d8d" }, 7]
            """#))
        #expect(loaded.config?.patterns[0].colorRules == [ColorRule(when: "debug", color: "#8d8d8d")])
        #expect(loaded.warnings.map(\.message) == [
            #"Pattern "log level": color rule #1's "when": unbalanced parenthesis (at character 1); skipped"#,
            ##"Pattern "log level": color rule #2's color "red" isn't like "#61afef" or { "light": …, "dark": … }; skipped"##,
            #"Pattern "log level": color rule #4 isn't { "when": "…", "color": "…" }; skipped"#,
        ])
    }

    @Test func aColorsValueThatIsntAListIsIgnoredSoTheDefaultsStay() throws {
        let loaded = load(config(colors: ##"{ "when": "warn", "color": "#ffc53d" }"##))
        let config = try #require(loaded.config)
        #expect(config.patterns[0].colorRules == nil)
        #expect(config.patterns[0].effectiveColorRules == Preset.logLevel.colorRules)
        #expect(loaded.warnings.map(\.message) == [
            #"Pattern "log level": "colors" must be a list of color rules; ignored"#,
        ])
        // Written back, it's kept as written, not turned into [] or dropped.
        let written = ConfigFile.encode(config)
        let text = try #require(String(data: written, encoding: .utf8))
        #expect(text.contains(##""colors": { "when": "warn", "color": "#ffc53d" }"##))
        let reloaded = ConfigFile.load(written)
        #expect(reloaded.config == config)
        #expect(try #require(reloaded.config).patterns[0].colorRules == nil)
        #expect(reloaded.warnings == loaded.warnings)
    }

    @Test func aRulesRegexIsReadAsAPatternsIsWithGrokAndPerlSpellings() throws {
        let loaded = load(#"""
            {
              "grok": { "SEVERE": "ERR|CRIT" },
              "patterns": [{
                "name": "log level", "regex": "\\b(?:ERROR|WARNING|DEBUG)\\b", "actions": ["copy"],
                "colors": [
                  { "when": "%{SEVERE}", "color": "#e5484d" },
                  { "when": "(?P<level>warn)|{", "color": "#ffc53d" },
                  { "when": "de\\Kbug", "color": "#8d8d8d" }
                ]
              }]
            }
            """#)
        #expect(loaded.warnings.map(\.message) == [
            #"Pattern "log level": color rule #3's "when": \K isn't supported; skipped"#,
        ])
        let config = try #require(loaded.config)
        let found = colors(line, config)
        #expect(found["ERROR"] == red)
        #expect(found["WARNING"] == amber)
    }

    @Test func rulesSurviveWritingTheFileBackAndReadingItAgain() throws {
        let loaded = try #require(load(config(colors: #"""
            [{ "when": "error", "color": { "light": "#cc0000", "dark": "#ff6666" } }]
            """#)).config)
        let again = try #require(ConfigFile.load(ConfigFile.encode(loaded)).config)
        #expect(again.patterns[0].colorRules == [
            ColorRule(when: "error", color: PatternColor(light: "#cc0000", dark: "#ff6666")),
        ])
        // Left out, it stays left out, so the defaults keep applying.
        let defaults = try #require(load(config(colors: nil)).config)
        #expect(try #require(ConfigFile.load(ConfigFile.encode(defaults)).config).patterns[0].colorRules == nil)
    }

    @Test func theInspectorsEntryCarriesItsMatchsColor() throws {
        let config = try #require(load(config(colors: ##"[{ "when": "warn", "color": "#ffc53d" }]"##)).config)
        let inspection = inspect(line, config: config, now: Date(), timeZone: .current, fileExists: { _ in true })
        let entries = try #require(inspection.tab(.pattern("log level"))).entries
        #expect(entries.first { $0.text == "WARNING" }?.color == amber)
        #expect(entries.first { $0.text == "ERROR" }?.color == config.resolvedColors[0])
    }

    @Test func aTabKeepsItsPatternsColorWhicheverMatchComesFirst() throws {
        let config = try #require(load(config(colors: ##"[{ "when": "warn", "color": "#ffc53d" }]"##)).config)
        let inspection = inspect(line, config: config, now: Date(), timeZone: .current, fileExists: { _ in true })
        let tab = try #require(inspection.tab(.pattern("log level")))
        #expect(tab.entries.first?.text == "WARNING")
        #expect(tab.entries.first?.color == amber)
        #expect(tab.color == config.color(ofName: "log level"))
    }
}
