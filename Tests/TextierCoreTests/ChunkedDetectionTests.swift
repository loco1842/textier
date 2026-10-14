import Foundation
import Synchronization
import Testing
@testable import TextierCore

/// A large text's regex Patterns run over line-aligned chunks on several cores;
/// what they find must be what one pass over the whole text finds.
@Suite("Detection in chunks")
struct ChunkedDetectionTests {
    /// Lines of every kind, a JSON object over several lines, and a block a
    /// multi-line User Pattern matches across many lines.
    static let text: String = {
        var lines: [String] = []
        for i in 0..<300 {
            switch i % 6 {
            case 0: lines.append(Fixtures.monologLine)
            case 1: lines.append(Fixtures.nginxAccessLine)
            case 2: lines.append(Fixtures.javaLogLines)
            case 3: lines.append("{\n  \"order\": \(i),\n  \"file\": \"/srv/app/x.php\",\n  \"line\": \(i)\n}")
            case 4: lines.append("BEGIN block \(i)\n" + String(repeating: "filler line ERROR\n", count: 20) + "END")
            default: lines.append("2026-10-11 09:41:\(String(format: "%02d", i % 60)) INFO see ~/logs/app.log:\(i) and https://x.test/\(i).")
            }
        }
        return lines.joined(separator: "\n")
    }()

    static var config: Config {
        var config = Config.default
        if let level = config.patterns.firstIndex(where: { $0.name == "log level" }) { config.patterns[level].enabled = true }
        config.patterns.append(Pattern(name: "block", regex: #"BEGIN[\s\S]*?END"#, actions: [.copy]))
        config.patterns.append(Pattern(name: "line start", regex: #"(?m)^\d{4}-\d\d"#, actions: [.copy]))
        config.patterns.append(Pattern(name: "line end", regex: #"(?m)\.$"#, actions: [.copy]))
        return config
    }

    func detected(chunkSize: Int?) -> [Match] {
        detect(
            Self.text, config: Self.config, budget: MatchingBudget(timeLimit: .seconds(60)), chunkSize: chunkSize
        )
    }

    @Test(arguments: [300, 1000, 4000])
    func chunksFindWhatTheWholeTextDoes(chunkSize: Int) {
        let whole = detected(chunkSize: nil)
        #expect(lineChunks(of: Self.text as NSString, size: chunkSize).count > 10)
        #expect(!whole.isEmpty)
        #expect(detected(chunkSize: chunkSize) == whole)
    }

    @Test func aMatchLongerThanTheOverlapIsFoundWhole() {
        let block = "BEGIN\n" + String(repeating: "filler line\n", count: 600) + "END"
        let text = Array(repeating: block, count: 4).joined(separator: "\n")
        let config = Config(patterns: [Pattern(name: "block", regex: #"BEGIN[\s\S]*?END"#, actions: [.copy])])
        let whole = detect(text, config: config, budget: MatchingBudget(timeLimit: .seconds(60)))
        let chunked = detect(text, config: config, budget: MatchingBudget(timeLimit: .seconds(60)), chunkSize: 1000)
        #expect(whole.count == 4)
        #expect(chunked == whole)
    }

    @Test func aMatchRunningIntoTheNextChunkLeavesItsSearchWhereOneSearchWould() {
        // Each "END tail" line starts a chunk. The block ends in it; one search goes
        // on from there and finds "tail", where the chunk's own search found
        // "D tail", which starts inside the block.
        let text = String(repeating: "BEGIN\nxx\nEND tail\n", count: 50)
        let config = Config(patterns: [Pattern(name: "p", regex: #"BEGIN[\s\S]*?END|D tail|tail"#, actions: [.copy])])
        let whole = detect(text, config: config, budget: MatchingBudget(timeLimit: .seconds(60)))
        let chunked = detect(text, config: config, budget: MatchingBudget(timeLimit: .seconds(60)), chunkSize: 7)
        #expect(whole.count == 100)
        #expect(chunked == whole)
    }

    @Test func chunksEndAtLineEndsAndCoverTheText() {
        let text = Self.text as NSString
        let chunks = lineChunks(of: text, size: 500)
        #expect(chunks.first?.location == 0)
        #expect(chunks.last.map(NSMaxRange) == text.length)
        for (chunk, next) in zip(chunks, chunks.dropFirst()) {
            #expect(NSMaxRange(chunk) == next.location)
            #expect(text.character(at: next.location - 1) == 0x0A)
        }
    }

    @Test func aShortTextIsOneChunk() {
        #expect(lineChunks(of: "a\nb\nc" as NSString) == [NSRange(location: 0, length: 5)])
    }

    @Test func aRunawayPatternsTimeIsSharedByItsChunks() {
        let runaway = Pattern(name: "runaway", regex: #"(?m)^(a+)+$"#, actions: [.copy])
        let text = Array(repeating: String(repeating: "a", count: 40) + "!", count: 64).joined(separator: "\n")
        let budget = MatchingBudget(timeLimit: .milliseconds(200))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = detect(text, config: Config(patterns: [runaway]), budget: budget, chunkSize: 100)
        }
        // Each chunk alone would take seconds; together they get 200 ms.
        #expect(elapsed < .milliseconds(1500))
        #expect(budget.stopped == ["runaway"])
    }

    @Test func theTimeLimitGrowsWithTheText() {
        #expect(Pattern.timeLimit(forLength: 0) == .seconds(2))
        #expect(Pattern.timeLimit(forLength: 2 * 1_048_576) == .seconds(2))
        #expect(Pattern.timeLimit(forLength: 10 * 1_048_576) == .seconds(10))
        #expect(Pattern.timeLimit(forLength: 100 * 1_048_576) == .seconds(100))
    }

    @Test func progressReachesTheEnd() {
        let reported = Mutex<[Double]>([])
        _ = detect(
            Self.text, config: Self.config, budget: MatchingBudget(), chunkSize: 1000,
            progress: { fraction in reported.withLock { $0.append(fraction) } }
        )
        let fractions = reported.withLock { $0 }
        #expect(fractions.count > 10)
        #expect(fractions.max() == 1)
        #expect(fractions.allSatisfy { $0 > 0 && $0 <= 1 })
    }
}
