import Foundation
import Testing
import TextierCore

/// How the core scales with a log's size, for `scripts/bench.sh`: runs only with
/// `TEXTIER_BENCH` set to the logs to time, comma-separated. Prints BENCH lines.
@Suite("Large log benchmark: core", .serialized)
struct LargeLogBenchmark {
    static let logs = (ProcessInfo.processInfo.environment["TEXTIER_BENCH"] ?? "")
        .split(separator: ",").map(String.init)

    @Test(.enabled(if: !logs.isEmpty)) func inspection() throws {
        var config = Config.default
        if let level = config.patterns.firstIndex(where: { $0.name == "log level" }) { config.patterns[level].enabled = true }
        let clock = ContinuousClock()
        for path in Self.logs {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let lines = text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            let mb = Double(text.utf8.count) / 1_048_576
            var matches: [Match] = []
            let detecting = clock.measure { matches = detect(text, config: config) }
            var inspection: Inspection?
            let inspecting = clock.measure {
                inspection = inspect(text, config: config, now: Date(), timeZone: .current, fileExists: { _ in false })
            }
            let entries = inspection?.tabs.reduce(0) { $0 + $1.entries.count } ?? 0
            print(String(
                format: "BENCH core lines=%d MB=%.1f detect=%.2fs inspect=%.2fs matches=%d entries=%d slow=%@",
                lines, mb, seconds(detecting), seconds(inspecting), matches.count, entries,
                (inspection?.slowPatterns ?? []).joined(separator: "+")
            ))
        }
    }
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
