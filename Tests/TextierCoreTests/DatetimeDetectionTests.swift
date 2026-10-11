import Testing
import TextierCore

@Suite("Datetime Preset detection")
struct DatetimeDetectionTests {
    let config = Config(patterns: [Preset.datetime])

    @Test func monologLineTimestampIsOneMatchOfferingCopy() throws {
        let matches = detect(Fixtures.monologLine, config: config)

        #expect(matches.map(\.text) == ["2026-10-07 11:17:10"])
        #expect(matches.first?.patternName == "datetime")
        #expect(matches.first?.actions == [.copy])
    }

    @Test(arguments: [
        ("on 2026-10-07 ok", "2026-10-07"),
        ("at 2026-10-07T11:17:10Z.", "2026-10-07T11:17:10Z"),
        ("at 2026-10-07T11:17:10.123456+07:00 ok", "2026-10-07T11:17:10.123456+07:00"),
        ("at 2026-10-07 11:17:10.5 ok", "2026-10-07 11:17:10.5"),
        ("at 2026-10-07T11:17 ok", "2026-10-07T11:17"),
        ("at 2026-10-07T11:17:10-0500 ok", "2026-10-07T11:17:10-0500"),
        (#"{"created_at":"2026-10-07T04:17:10.000000Z"}"#, "2026-10-07T04:17:10.000000Z"),
        ("ts=1696680000 next", "1696680000"),
        ("ts=1696680000123 next", "1696680000123"),
    ])
    func positives(input: String, expected: String) {
        #expect(detect(input, config: config).map(\.text) == [expected])
    }

    @Test(arguments: [
        "2026-13-07",
        "2026-10-32",
        "12026-10-07",
        "2026-10-071",
        "26-10-07",
        "2026/10/07",
        "id 12345678901 here",
        "id 123456789012 here",
        "id 12345678901234 here",
        "id 123456789 here",
        "abc1696680000",
        "1696680000abc",
    ])
    func nearMissesAreNotMatches(input: String) {
        #expect(detect(input, config: config).isEmpty)
    }
}
