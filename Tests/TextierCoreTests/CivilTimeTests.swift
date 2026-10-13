import Foundation
import Testing
@testable import TextierCore

/// `CivilTime`'s arithmetic stands in for a `Calendar`: it must agree with one.
@Suite("Datetimes by arithmetic agree with a Calendar")
struct CivilTimeTests {
    /// Instants from 1600 to 2400, and around today, in steps that land on every
    /// time of day and day of the year sooner or later.
    static let instants: [Int64] = {
        var instants: [Int64] = []
        var ms: Int64 = -11_676_096_000_000  // 1600-01-01
        while ms < 13_569_465_600_000 {  // 2400-01-01
            instants.append(ms)
            ms += 1_234_567_891_237
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for step in stride(from: -400 * 86_400_000 as Int64, through: 400 * 86_400_000, by: 3_600_007) {
            instants.append(now + step)
        }
        return instants
    }()

    static let zones = ["UTC", "Asia/Ho_Chi_Minh", "America/New_York", "Europe/London", "Australia/Lord_Howe", "Asia/Kathmandu"]
        .compactMap(TimeZone.init(identifier:))

    @Test func wallTimesMatch() {
        for ms in Self.instants {
            #expect(wallTime(ms, fractional: true) == calendarWallTime(ms, fractional: true))
            #expect(wallTime(ms, fractional: false) == calendarWallTime(ms, fractional: false))
        }
        // Before 1600 the Calendar's own answer is used.
        let early: Int64 = -14_000_000_000_000
        #expect(wallTime(early, fractional: false) == calendarWallTime(early, fractional: false))
    }

    @Test func summariesMatchInEveryZone() {
        let now = Date()
        for zone in Self.zones {
            for ms in Self.instants {
                let conversions = DatetimeConversions(milliseconds: ms, fractional: false, timeZone: zone, now: now)
                #expect(
                    conversions.summary(now: now, timeZone: zone) == conversions.calendarSummary(now: now, timeZone: zone),
                    "\(ms) in \(zone.identifier)"
                )
            }
        }
    }

    @Test func writtenDatetimesReadTheSameInEveryZone() throws {
        var texts: [String] = []
        for ms in Self.instants.prefix(400) {
            texts.append(calendarWallTime(ms, fractional: false).replacingOccurrences(of: "T", with: " "))
        }
        // Daylight saving changes: a skipped hour and a repeated one, in New York and London.
        texts += ["2026-03-08 02:30:00", "2026-11-01 01:30:00", "2026-03-29 01:30:00", "2026-10-25 01:30:00"]
        // Out of range, which the Calendar reads leniently.
        texts += ["2026-02-31 10:00:00", "2026-13-01 10:00:00", "1500-06-01 12:00:00"]
        for zone in Self.zones {
            for text in texts {
                let written = try #require(WrittenDatetime(text), "\(text)")
                #expect(written.milliseconds(in: zone) == written.calendarMilliseconds(in: zone), "\(text) in \(zone.identifier)")
            }
        }
    }

    @Test func daysRoundTrip() {
        for days in stride(from: -200_000 as Int64, through: 200_000, by: 37) {
            let date = CivilTime.date(days: days)
            #expect(CivilTime.days(year: date.year, month: date.month, day: date.day) == days)
        }
    }
}
