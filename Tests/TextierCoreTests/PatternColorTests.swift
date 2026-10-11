import Foundation
import Testing
import TextierCore

@Suite("Pattern colors")
struct PatternColorTests {
    /// A v1 config: the shipped Patterns as they were, with no colors.
    let colorless = Config(patterns: Config.default.patterns.map { pattern in
        var pattern = pattern
        pattern.color = nil
        return pattern
    })

    func color(of name: String, in config: Config) throws -> PatternColor {
        config.color(of: try #require(config.patterns.first { $0.name == name }))
    }

    @Test func everyPresetAndBuiltinHasADistinctDefaultColor() throws {
        let colors = try colorless.patterns.map { try color(of: $0.name, in: colorless) }

        #expect(Set(colors).count == colors.count)
        #expect(Set(colors.map(\.light)).count == colors.count)
        #expect(Set(colors.map(\.dark)).count == colors.count)
    }

    @Test func theDefaultConfigWritesTheSameColorsAColorlessConfigResolvesTo() throws {
        for pattern in Config.default.patterns {
            #expect(pattern.color != nil)
            #expect(Config.default.color(of: pattern) == (try color(of: pattern.name, in: colorless)))
        }
    }

    @Test func aFirstLaunchConfigFileWritesTheRadixColors() {
        let text = String(decoding: ConfigFile.encode(Config.default), as: UTF8.self)

        for hex in ["#ffc53d", "#ef5f00", "#0090ff", "#6e56cf", "#46a758", "#e5484d"] {
            #expect(text.contains(#""color": "\#(hex)""#))
        }
    }

    @Test func monologMatchesCarryTheirPatternsPaletteColor() throws {
        var config = colorless
        config.patterns[5].enabled = true
        // The Pattern's own color, not its Color Rules'.
        config.patterns[5].colorRules = []
        let matches = detect(Fixtures.monologLine, config: config)

        let byName = Dictionary(matches.map { ($0.patternName, $0.color) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["datetime"] == (try color(of: "datetime", in: config)))
        #expect(byName["json"] == (try color(of: "json", in: config)))
        #expect(byName["log level"] == (try color(of: "log level", in: config)))
        #expect(Set([byName["datetime"], byName["json"], byName["log level"]]).count == 3)

        let json = try #require(matches.first { $0.patternName == "json" })
        #expect(json.children.first { $0.patternName == "url" }?.color == (try color(of: "url", in: config)))
    }

    @Test func anExplicitColorWins() throws {
        var config = colorless
        config.patterns[2].color = PatternColor(light: "#112233", dark: "#445566")
        let matches = detect("go http://a.test now", config: config)

        #expect(matches.first?.color == PatternColor(light: "#112233", dark: "#445566"))
    }

    @Test func userPatternsTakeTheNextUnusedPaletteColorsInConfigOrder() throws {
        let ticket = Pattern(name: "ticket", regex: #"\bJIRA-\d+\b"#, actions: [.copy])
        let user = Pattern(name: "user", regex: #"@\w+"#, actions: [.copy])
        let config = Config(patterns: colorless.patterns + [ticket, user])

        let all = try config.patterns.map { try color(of: $0.name, in: config) }
        #expect(Set(all).count == all.count)
        #expect(try color(of: "ticket", in: config) == Palette.forUserPatterns[0])
        #expect(try color(of: "user", in: config) == Palette.forUserPatterns[1])
    }

    @Test func aUserPatternSkipsAPaletteColorAnotherPatternUsesExplicitly() throws {
        let first = Pattern(name: "first", regex: "a", actions: [.copy], color: Palette.forUserPatterns[0])
        let second = Pattern(name: "second", regex: "b", actions: [.copy])
        let config = Config(patterns: [second, first])

        #expect(try color(of: "first", in: config) == Palette.forUserPatterns[0])
        #expect(try color(of: "second", in: config) == Palette.forUserPatterns[1])
    }

    @Test func manyUserPatternsStillAllGetAColor() throws {
        let patterns = (0..<20).map { Pattern(name: "p\($0)", regex: "x\($0)", actions: [.copy]) }
        let config = Config(patterns: patterns)

        let colors = try patterns.map { try color(of: $0.name, in: config) }
        #expect(colors.count == 20)
        #expect(Set(colors.prefix(Palette.forUserPatterns.count)).count == Palette.forUserPatterns.count)
    }

    @Test func aNameResolvesToItsGroupsColorOrElseThePalette() throws {
        let ticket = Pattern(name: "ticket", regex: "x", actions: [.copy])
        let config = Config(patterns: colorless.patterns + [ticket])

        #expect(config.color(ofName: "ticket") == (try color(of: "ticket", in: config)))
        #expect(config.color(ofName: "json") == Palette.byName["json"])
        #expect(Config(patterns: []).color(ofName: "url") == Palette.byName["url"])
        #expect(Config(patterns: []).color(ofName: "nothing") == Palette.fallback)
    }

    @Test func aSingleHexFillsBothAppearances() {
        let color = PatternColor("#e5c07b")

        #expect(color.light == "#e5c07b")
        #expect(color.dark == "#e5c07b")
        #expect(color.isSingle)
        #expect(!PatternColor(light: "#000000", dark: "#ffffff").isSingle)
    }
}

@Suite("Color roles")
struct ColorRoleTests {
    /// Every color textier ships: the Presets' and Built-ins', User Patterns', Plain Text's.
    static let shipped = Array(Palette.byName.values) + Palette.forUserPatterns + [Palette.plainText]

    @Test(arguments: shipped, [Appearance.light, .dark])
    func textReadsOnThePaneAndOnSolidReadsOnTheSolid(color: PatternColor, appearance: Appearance) throws {
        let roles = color.roles(in: appearance)

        #expect(try contrast(roles.text, Pane.color(in: appearance)) >= 6)
        #expect(try contrast(roles.text, composite(roles.strongTint, over: Pane.color(in: appearance))) >= 6)
        #expect(try contrast(roles.onSolid, roles.solid) >= 3)
    }

    @Test func amberTakesDarkTextOnItsSolidAndBlueTakesWhite() throws {
        for appearance in [Appearance.light, .dark] {
            let amber = try #require(Palette.byName["json"]).roles(in: appearance)
            let blue = try #require(Palette.byName["url"]).roles(in: appearance)
            #expect(try luminance(amber.onSolid) < 0.1)
            #expect(blue.onSolid == "#ffffff")
        }
    }

    @Test func theDefaultsAreTheRadixHues() {
        #expect(Palette.byName == [
            "json": "#ffc53d", "escaped-json": "#ef5f00", "url": "#0090ff",
            "datetime": "#6e56cf", "file path": "#46a758", "log level": "#e5484d",
        ])
        #expect(Palette.forUserPatterns == ["#d6409f", "#00a2c7", "#bdee63", "#8e4ec6", "#8d8d8d"])
    }

    @Test func theSolidIsTheColorAndTheTintsAreItTranslucent() {
        let roles = PatternColor("#0090ff").roles(in: .light)

        #expect(roles.solid == "#0090ff")
        #expect(roles.tint.hasPrefix("#0090ff") && roles.tint.count == 9)
        #expect(roles.strongTint.hasPrefix("#0090ff") && roles.strongTint.count == 9)
        #expect(roles.tint < roles.strongTint)
    }

    @Test func aPairResolvesEachHalfInItsAppearance() {
        let color = PatternColor(light: "#0550ae", dark: "#79c0ff")

        #expect(color.roles(in: .light).solid == "#0550ae")
        #expect(color.roles(in: .dark).solid == "#79c0ff")
        #expect(PatternColor("#e5c07b").roles(in: .light).solid == PatternColor("#e5c07b").roles(in: .dark).solid)
    }

    @Test func aColorWithItsOwnAlphaKeepsItAsTheTint() {
        let roles = PatternColor("#61afef40").roles(in: .dark)

        #expect(roles.tint == "#61afef40")
        #expect(roles.solid == "#61afef")
        #expect(roles.strongTint > roles.tint)
    }

    @Test func textDarkensInLightModeAndLightensInDarkMode() throws {
        let amber = PatternColor("#ffc53d")

        #expect(try luminance(amber.roles(in: .light).text) < luminance("#ffc53d"))
        #expect(try luminance(PatternColor("#6e56cf").roles(in: .dark).text) > luminance("#6e56cf"))
    }

    @Test func anUnreadableValueStillGetsRoles() {
        let roles = PatternColor("nonsense").roles(in: .light)

        #expect(roles.solid == Palette.fallback.light)
    }
}

/// The WCAG contrast ratio of two opaque `#rrggbb` colors.
func contrast(_ first: String, _ second: String) throws -> Double {
    let (a, b) = (try luminance(first), try luminance(second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

func luminance(_ hex: String) throws -> Double {
    try #require(RGBColor(hex: hex)).luminance
}

func composite(_ top: String, over bottom: String) throws -> String {
    try #require(RGBColor(hex: top)).composited(over: try #require(RGBColor(hex: bottom))).hex
}
