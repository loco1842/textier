import Foundation
import Testing
import TextierCore

@Suite("Patterns that share a name")
struct SharedPatternNameTests {
    static let float = Pattern(name: "numeric", regex: #"\b\d+\.\d+\b"#, actions: [.copy])
    static let integer = Pattern(name: "numeric", regex: #"\b\d+\b"#, actions: [.copy, .open])
    let config = Config(patterns: [Builtin.json, float, integer])

    @Test func aFloatIsOneMatchAndAnIntegerAnother() {
        let matches = detect("pi is 3.14, the answer 42", config: config)

        #expect(matches.map(\.text) == ["3.14", "42"])
        #expect(matches.map(\.patternName) == ["numeric", "numeric"])
        #expect(matches.allSatisfy { $0.children.isEmpty })
    }

    @Test func eachMatchKeepsTheActionsOfThePatternThatFoundIt() {
        let matches = detect("pi is 3.14, the answer 42", config: config)

        #expect(matches.map(\.actions) == [[.copy], [.copy, .open]])
        #expect(matches.map(\.patternIndex) == [1, 2])
    }

    @Test func longestWinsAcrossSameNamePatternsThenConfigOrder() {
        let wide = Pattern(name: "id", regex: #"[A-Z]+-\d+"#, actions: [.copy])
        let narrow = Pattern(name: "id", regex: #"\d+-\d+"#, actions: [.open])
        let config = Config(patterns: [narrow, wide])

        #expect(detect("ABC-12-34", config: config).map(\.text) == ["ABC-12"])
        // `AB-12` and `12-34` overlap and are the same length; the earlier Pattern wins.
        let tie = detect("AB-12-34", config: config)
        #expect(tie.map(\.text) == ["12-34"])
        #expect(tie.map(\.actions) == [[.open]])
    }

    @Test func theyShowAsOneTabInOneColor() throws {
        let inspection = inspectFixed("pi is 3.14, the answer 42", config: config)
        let tab = try #require(inspection.tab(.pattern("numeric")))

        #expect(inspection.tabs.map(\.title) == ["numeric", "Plain Text"])
        #expect(tab.entries.map(\.text) == ["3.14", "42"])
        #expect(tab.entries.map(\.actions) == [[.copy], [.copy, .open]])
        #expect(Set(inspection.matches.map(\.color)).count == 1)
        #expect(tab.color == inspection.matches.first?.color)
    }

    @Test func aNamesColorIsItsFirstPatterns() {
        var float = Self.float
        float.color = "#112233"
        var integer = Self.integer
        integer.color = "#445566"
        let config = Config(patterns: [float, integer])

        #expect(config.color(of: integer) == "#112233")
        #expect(detect("3.14 42", config: config).map(\.color) == ["#112233", "#112233"])
    }

    @Test func userPatternsAreGivenPaletteColorsPerName() {
        let ticket = Pattern(name: "ticket", regex: #"[A-Z]+-\d+"#, actions: [.copy])
        let config = Config(patterns: [Self.float, Self.integer, ticket])

        #expect(config.resolvedColors == [
            Palette.forUserPatterns[0], Palette.forUserPatterns[0], Palette.forUserPatterns[1],
        ])
    }

    @Test func aStringValueMatchPointsAtItsPatternInTheConfig() throws {
        let match = try #require(stringValueMatch("http://a.test/x", config: .default))

        #expect(Config.default.patterns[match.patternIndex] == Preset.url)
    }
}
