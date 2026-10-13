import AppKit
import Darwin
import Testing
import TextierCore
@testable import Textier

/// The Panel with a large log, for `scripts/bench.sh`: runs only with
/// `TEXTIER_BENCH` set to the logs to time, comma-separated. Prints BENCH lines.
private let benchmarkLogs = (ProcessInfo.processInfo.environment["TEXTIER_BENCH"] ?? "")
    .split(separator: ",").map(String.init)

extension AppTests {
    @MainActor
    @Suite("Large log benchmark: Panel", .serialized)
    struct LargeLogBenchmark {
        @Test(.enabled(if: !benchmarkLogs.isEmpty)) func panel() async throws {
            try await runInApp {
                for path in benchmarkLogs {
                    let app = try AppHarness()
                    defer { app.tearDown() }
                    var config = Config.default
                    if let level = config.patterns.firstIndex(where: { $0.name == "log level" }) { config.patterns[level].enabled = true }
                    try app.writeConfig(config)
                    let text = try String(contentsOfFile: path, encoding: .utf8)
                    let lines = text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
                    let clock = ContinuousClock()
                    let memoryBefore = residentMB()

                    let start = clock.now
                    app.controller.show(input: text)
                    waitForInspection(app)
                    app.panel.displayIfNeeded()
                    let shown = clock.now - start
                    let memory = residentMB() - memoryBefore

                    let select = clock.measure {
                        try? app.select("json", 0)
                        app.panel.displayIfNeeded()
                    }
                    let scroll = clock.measure {
                        app.textView.scrollToEndOfDocument(nil)
                        app.panel.displayIfNeeded()
                    }
                    var keystroke = Duration.zero
                    let reinspection = clock.measure {
                        keystroke = clock.measure {
                            app.textView.setSelectedRange(NSRange(location: 0, length: 0))
                            app.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
                            app.panel.displayIfNeeded()
                        }
                        app.spin(0.35)
                        waitForInspection(app)
                    }
                    print(String(
                        format: "BENCH panel lines=%d shown=%.2fs select=%.3fs scrollToEnd=%.3fs keystroke=%.3fs reinspection=%.2fs memoryMB=%d",
                        lines, seconds(shown), seconds(select), seconds(scroll), seconds(keystroke), seconds(reinspection),
                        Int(memory)
                    ))
                }
            }
        }

        private func waitForInspection(_ app: AppHarness) {
            let clock = ContinuousClock()
            let start = clock.now
            repeat { app.spin(0.02) } while (app.model.isInspecting || app.model.inspection.matches.isEmpty)
                && clock.now - start < .seconds(600)
        }

        private func residentMB() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
        }

        private func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
    }
}
