import Foundation
import Testing
@testable import TextierCore

@Suite("Sorting a tab's entries")
struct EntryOrderTests {
    func tab(_ name: String, in text: String, config: Config = .default) throws -> InspectorTab {
        let inspection = inspect(
            text, config: config, now: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: TimeZone(identifier: "UTC")!, fileExists: { _ in false }
        )
        return try #require(inspection.tab(name == "Plain Text" ? .plainText : .pattern(name)))
    }

    func texts(_ tab: InspectorTab, _ order: EntryOrder) -> [String] {
        tab.indices(in: order).map { tab.entries[$0].text }
    }

    @Test func datetimesSortByTheInstantTheyMeanWhateverTheirForm() throws {
        // 10:00 UTC, 09:00 at +07:00 (02:00 UTC), an epoch (2025-10-09 07:33 UTC), 08:00 UTC.
        let datetimes = try tab("datetime", in: "a 2026-10-11 10:00:00Z b 2026-10-11T09:00:00+07:00 c 1760000000 d 2026-10-11 08:00")
        #expect(datetimes.sortKind == .time)
        #expect(texts(datetimes, .position) == ["2026-10-11 10:00:00Z", "2026-10-11T09:00:00+07:00", "1760000000", "2026-10-11 08:00"])
        #expect(texts(datetimes, .ascending) == ["1760000000", "2026-10-11T09:00:00+07:00", "2026-10-11 08:00", "2026-10-11 10:00:00Z"])
        #expect(texts(datetimes, .descending) == ["2026-10-11 10:00:00Z", "2026-10-11 08:00", "2026-10-11T09:00:00+07:00", "1760000000"])
        #expect(SortKind.time.title(of: .descending) == "Latest first")
    }

    @Test func tiesKeepTheirOrderAndUnreadableValuesComeLastEitherWay() throws {
        var config = Config.default
        // A datetime Pattern loose enough to match what doesn't read as one.
        let index = try #require(config.patterns.firstIndex { $0.name == "datetime" })
        config.patterns[index].kind = .regex(#"\b\d{4}-\d{2}-\w{2}(?: \d{2}:\d{2})?\b"#)
        let datetimes = try tab("datetime", in: "2026-10-11 10:00 x 2026-10-xx y 2026-10-11 10:00 z 2026-10-10 10:00", config: config)
        #expect(datetimes.entries.map(\.text) == ["2026-10-11 10:00", "2026-10-xx", "2026-10-11 10:00", "2026-10-10 10:00"])
        #expect(datetimes.indices(in: .ascending) == [3, 0, 2, 1])
        #expect(datetimes.indices(in: .descending) == [0, 2, 3, 1])
    }

    @Test func filePathsSortByPathThenLineAsANumber() throws {
        let paths = try tab("file path", in: "/b/x.php:9 /a/y.php:120 /a/y.php:80 /a/y.php:9")
        #expect(paths.sortKind == .path)
        #expect(texts(paths, .ascending) == ["/a/y.php:9", "/a/y.php:80", "/a/y.php:120", "/b/x.php:9"])
        #expect(texts(paths, .descending) == ["/b/x.php:9", "/a/y.php:120", "/a/y.php:80", "/a/y.php:9"])
    }

    @Test func textSortsWithNumbersAsNumbersAndCaseIgnored() throws {
        var config = Config.default
        config.patterns.append(Pattern(name: "order", regex: #"\b[A-Za-z]+-\d+\b"#, actions: [.copy]))
        let orders = try tab("order", in: "ORD-10 ord-9 ORD-100 abc-2 ORD-09", config: config)
        #expect(orders.sortKind == .text)
        #expect(texts(orders, .ascending) == ["abc-2", "ord-9", "ORD-09", "ORD-10", "ORD-100"])
        #expect(texts(orders, .descending) == ["ORD-100", "ORD-10", "ord-9", "ORD-09", "abc-2"])
        #expect(SortKind.text.title(of: .ascending) == "A → Z")
    }

    @Test func plainTextKeepsItsOrder() throws {
        let plain = try tab("Plain Text", in: "zebra https://a.test apple https://b.test mango")
        #expect(plain.sortKind == nil)
        #expect(plain.indices(in: .ascending) == plain.indices(in: .position))
    }

    @Test func naturalTextComparesNumbersByValue() {
        func compare(_ a: String, _ b: String) -> ComparisonResult { NaturalText(a).compare(NaturalText(b)) }
        #expect(compare("ORD-9", "ORD-10") == .orderedAscending)
        #expect(compare("ord-009", "ORD-9") == .orderedSame)
        #expect(compare("a", "a1") == .orderedAscending)
        #expect(compare("v2.10", "v2.9") == .orderedDescending)
    }

    @Test func sortingAHundredThousandEntriesIsQuick() throws {
        var config = Config.default
        config.patterns.append(Pattern(name: "order", regex: #"\bORD-\d+\b"#, actions: [.copy]))
        let text = (0..<100_000).map { "ORD-\(($0 * 7919) % 100_000)" }.joined(separator: " ")
        let orders = try tab("order", in: text, config: config)
        let clock = ContinuousClock()
        var sorted: [Int] = []
        let elapsed = clock.measure { sorted = orders.indices(in: .ascending) }
        #expect(sorted.count == 100_000)
        #expect(orders.entries[sorted[0]].text == "ORD-0")
        // Against sorting the same texts plainly, timed alongside, so a busy machine
        // slows both; comparing character by character was many times slower.
        let plain = clock.measure { _ = orders.entries.map(\.text).sorted(by: <) }
        #expect(elapsed < plain * 8 + .milliseconds(200))
    }
}
