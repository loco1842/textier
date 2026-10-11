import Testing
import TextierCore

@Suite("Log level Preset detection")
struct LogLevelDetectionTests {
    var enabledLogLevel: Pattern {
        var logLevel = Preset.logLevel
        logLevel.enabled = true
        return logLevel
    }

    @Test func shipsDisabled() {
        #expect(Preset.logLevel.enabled == false)
        #expect(detect(Fixtures.monologLine, config: Config(patterns: [Preset.logLevel])).isEmpty)
    }

    @Test func enabledItFindsTheMonologLevelOfferingCopy() throws {
        let matches = detect(Fixtures.monologLine, config: Config(patterns: [enabledLogLevel]))

        #expect(matches.map(\.text) == ["WARNING"])
        #expect(matches.first?.patternName == "log level")
        #expect(matches.first?.actions == [.copy])
    }

    @Test(arguments: ["EMERGENCY", "ALERT", "CRITICAL", "ERROR", "WARNING", "NOTICE", "INFO", "DEBUG"])
    func everyPSR3LevelIsAMatch(level: String) {
        #expect(detect("local.\(level): boom", config: Config(patterns: [enabledLogLevel])).map(\.text) == [level])
    }

    @Test(arguments: ["WARNINGS", "XERROR", "INFORMATION", "DEBUGGER", "FATAL"])
    func nearMissesAreNotMatches(input: String) {
        #expect(detect("local.\(input): boom", config: Config(patterns: [enabledLogLevel])).isEmpty)
    }
}

@Suite("Default Config")
struct DefaultConfigTests {
    @Test func listsTheBuiltinsThenURLDatetimeFilePathThenDisabledLogLevel() {
        #expect(Config.default.patterns == [
            Builtin.json, Builtin.escapedJSON, Preset.url, Preset.datetime, Preset.filePath, Preset.logLevel,
        ])
        #expect(Config.default.patterns.map(\.enabled) == [true, true, true, true, true, false])
    }

    @Test func monologLineShowsDatetimeAndJSONHoldingURLAndFilePathsButNoLogLevel() {
        let matches = detect(Fixtures.monologLine, config: .default)

        #expect(matches.map(\.patternName) == ["datetime", "json"])
        #expect(matches.last?.children.map(\.patternName) == ["url"] + Array(repeating: "file path", count: 6))
    }
}
