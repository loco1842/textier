import Foundation

/// Gregorian dates and wall times by arithmetic on days since 1970-01-01, in
/// place of a `Calendar`, which takes microseconds a call: a large log has
/// hundreds of thousands of datetimes, each worked out several ways. Only for
/// years 1600–9999 (`years`): Foundation's Gregorian calendar is Julian before
/// 1582, and callers fall back to a `Calendar` outside the range.
enum CivilTime {
    static let years: ClosedRange<Int64> = 1600...9999

    /// Days from 1970-01-01 to `year`-`month`-`day`. A day past its month's end
    /// runs into the next month, as a lenient `Calendar` reads it. After Howard
    /// Hinnant's `days_from_civil`.
    static func days(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The date `days` after 1970-01-01. After Howard Hinnant's `civil_from_days`.
    static func date(days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// The wall time `seconds` after the epoch, read as UTC: its date, its time of
    /// day in seconds, and its day number; nil outside `years`.
    static func wallTime(seconds: Int64) -> (year: Int64, month: Int64, day: Int64, secondOfDay: Int64, dayNumber: Int64)? {
        let dayNumber = floorDivision(seconds, 86_400)
        let date = date(days: dayNumber)
        guard years.contains(date.year) else { return nil }
        return (date.year, date.month, date.day, seconds - dayNumber * 86_400, dayNumber)
    }

    /// `2026-10-07` for a date.
    static func dateText(year: Int64, month: Int64, day: Int64) -> String {
        padded(year, 4) + "-" + padded(month, 2) + "-" + padded(day, 2)
    }

    /// `04:17:10` for a time of day in seconds.
    static func timeText(secondOfDay: Int64) -> String {
        padded(secondOfDay / 3600, 2) + ":" + padded(secondOfDay / 60 % 60, 2) + ":" + padded(secondOfDay % 60, 2)
    }

    /// `value` with leading zeros to `width` digits, as `%0Nd` writes it.
    static func padded(_ value: Int64, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// The instant whose wall time in `zone` is `naive` (seconds after the epoch,
    /// read as UTC), when that's certain: nil near an offset change in `zone` (a
    /// time skipped or repeated by daylight saving), where a `Calendar` decides.
    static func instant(ofWallTime naive: Int64, in zone: TimeZone) -> Int64? {
        func offset(_ seconds: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(seconds))))
        }
        let guess = offset(naive)
        let instant = naive - guess
        // The same offset a day either side: no change near this wall time.
        guard offset(instant) == guess, offset(instant - 86_400) == guess, offset(instant + 86_400) == guess
        else { return nil }
        return instant
    }
}

func floorDivision(_ value: Int64, _ divisor: Int64) -> Int64 {
    let quotient = value / divisor
    return value % divisor < 0 ? quotient - 1 : quotient
}
