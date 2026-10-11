import Foundation
import Testing
import TextierCore

@Suite("A time limit for each Pattern's matching")
struct PatternTimeLimitTests {
    /// Matches `ok` at once, then backtracks catastrophically on the run of `a`s
    /// that doesn't end the text.
    let runaway = Pattern(name: "runaway", regex: "ok|(a+)+$", actions: [.copy])
    let input = "ok " + String(repeating: "a", count: 40) + "!"

    func inspectFixed(
        _ input: String, config: Config, timeLimit: Duration, isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> Inspection {
        inspect(
            input, config: config, now: InspectionClock.now, timeZone: InspectionClock.zone,
            homeDirectory: "/Users/dev", timeLimit: timeLimit, isCancelled: isCancelled, fileExists: { _ in false }
        )
    }

    @Test func aRunawayPatternIsStoppedKeepsItsMatchesSoFarAndIsReported() {
        let clock = ContinuousClock()
        var inspection: Inspection?
        let elapsed = clock.measure {
            inspection = inspectFixed(input, config: Config(patterns: [runaway]), timeLimit: .milliseconds(200))
        }

        #expect(elapsed < .seconds(1.5))
        #expect(inspection?.slowPatterns == ["runaway"])
        #expect(inspection?.matches.map(\.text) == ["ok"])
    }

    @Test func otherPatternsStillRunAndAreNotReported() {
        let inspection = inspectFixed(
            input + " https://a.test/x", config: Config(patterns: [runaway, Preset.url]), timeLimit: .milliseconds(200)
        )

        #expect(inspection.slowPatterns == ["runaway"])
        #expect(inspection.matches.map(\.patternName) == ["runaway", "url"])
    }

    @Test func shippedPatternsOverALogReportNothing() {
        let log = Array(repeating: Fixtures.monologLine, count: 20).joined(separator: "\n")
        let inspection = inspectFixed(log, config: .default, timeLimit: Pattern.timeLimit)

        #expect(inspection.slowPatterns == [])
        #expect(inspection.matches.count == 40)
    }

    // MARK: One time limit per Pattern for the whole inspection

    /// Opens a URL, so a Field value is matched against it too (`stringValueMatch`).
    /// Anchored, it fails at once over the whole Input but backtracks
    /// catastrophically over a Field value of `a`s that doesn't end with one.
    let runawayLink = Pattern(name: "runaway", regex: "^(a+)+$", actions: [.openURL])
    let values = Pattern(name: "values", regex: #"v=(?<v>\S+)"#, actions: [.copy])
    let value = "v=" + String(repeating: "a", count: 40) + "!"

    @Test func aPatternRunningOutOfTimeOnAFieldValueIsReported() {
        let inspection = inspectFixed(value, config: Config(patterns: [runawayLink, values]), timeLimit: .milliseconds(200))

        #expect(inspection.matches.map(\.patternName) == ["values"])
        #expect(inspection.slowPatterns == ["runaway"])
    }

    @Test func aPatternsTimeIsSharedByEveryFieldValue() {
        let input = Array(repeating: value, count: 5).joined(separator: " ")
        let clock = ContinuousClock()
        var inspection: Inspection?
        let elapsed = clock.measure {
            inspection = inspectFixed(input, config: Config(patterns: [runawayLink, values]), timeLimit: .milliseconds(200))
        }

        // A time limit for each value would take 5 of them.
        #expect(elapsed < .milliseconds(700))
        #expect(inspection?.matches.count == 5)
        #expect(inspection?.slowPatterns == ["runaway"])
    }

    @Test func aPatternWhoseTimeRanOutOverShortPassesIsReportedToo() {
        // Each pass is too short to be cut off; together they use up the time.
        let inspection = inspectFixed(
            "v=a.test v=b.test", config: Config(patterns: [Preset.url, values]), timeLimit: .nanoseconds(1)
        )

        #expect(inspection.slowPatterns.contains("url"))
    }

    // MARK: Cancelling

    @Test func aCancelledInspectionStopsARunningPatternAtOnce() {
        let start = ContinuousClock.now
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = inspectFixed(
                input, config: Config(patterns: [runaway]), timeLimit: .seconds(2),
                isCancelled: { ContinuousClock.now - start > .milliseconds(50) }
            )
        }

        #expect(elapsed < .milliseconds(700))
    }

    @Test func aCancelledInspectionRunsNoMorePatternsAndReportsNoneAsSlow() {
        let clock = ContinuousClock()
        var inspection: Inspection?
        let elapsed = clock.measure {
            inspection = inspectFixed(
                input, config: Config(patterns: [runaway, runaway]), timeLimit: .seconds(2), isCancelled: { true }
            )
        }

        #expect(elapsed < .milliseconds(700))
        #expect(inspection?.slowPatterns == [])
    }
}
