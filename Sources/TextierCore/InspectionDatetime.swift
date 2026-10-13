import Foundation

/// A datetime Match converted, or nil when `text` isn't a form the `datetime`
/// Preset matches. `YYYY-MM-DD[ T]HH:MM[:SS[.fff]]` with `Z` or an offset uses it;
/// without one it's read in `timeZone` (a date alone at local midnight) and also
/// re-read as UTC. A 10-digit epoch is seconds and a 13-digit one milliseconds,
/// both UTC. Everything is kept to the millisecond.
func datetimeDetail(_ text: String, now: Date, timeZone: TimeZone) -> DatetimeDetail? {
    let utc = TimeZone(secondsFromGMT: 0)!
    if text.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
       [10, 13].contains(text.utf8.count), let value = Int64(text) {
        let milliseconds = text.utf8.count == 13 ? value : value * 1000
        let conversions = DatetimeConversions(
            milliseconds: milliseconds, fractional: text.utf8.count == 13, timeZone: timeZone, now: now
        )
        return DatetimeDetail(assumedLocal: false, conversions: conversions, asUTC: nil)
    }

    guard let written = WrittenDatetime(text) else { return nil }
    func conversions(readIn zone: TimeZone) -> DatetimeConversions? {
        written.milliseconds(in: zone).map {
            DatetimeConversions(milliseconds: $0, fractional: written.fraction != nil, timeZone: timeZone, now: now)
        }
    }
    if let offset = written.offsetSeconds {
        guard let zone = TimeZone(secondsFromGMT: offset), let read = conversions(readIn: zone) else { return nil }
        return DatetimeDetail(assumedLocal: false, conversions: read, asUTC: nil)
    }
    guard let local = conversions(readIn: timeZone), let asUTC = conversions(readIn: utc) else { return nil }
    return DatetimeDetail(assumedLocal: true, conversions: local, asUTC: asUTC)
}

/// The fields of a written datetime, before any time zone is applied. A `datetime`
/// Pattern's regex may match digits other than ASCII ones (ICU's `\d` does); text
/// with those isn't read.
struct WrittenDatetime {
    private static let format = try! NSRegularExpression(
        pattern: #"^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[T ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]+))?)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$"#
    )

    var fields: DateComponents
    /// The fractional seconds' digits, when written.
    var fraction: String?
    /// The written offset from UTC; nil when there's none.
    var offsetSeconds: Int?

    init?(_ text: String) {
        let ns = text as NSString
        guard let match = Self.format.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        /// A group's number, 0 when it isn't written; nil when it doesn't read as one.
        func number(_ index: Int) -> Int? {
            guard let digits = group(index) else { return 0 }
            return Int(digits)
        }
        guard let year = number(1), let month = number(2), let day = number(3), let hour = number(4),
              let minute = number(5), let second = number(6)
        else { return nil }
        fields = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        fraction = group(7)
        switch group(8) {
        case nil:
            offsetSeconds = nil
        case "Z":
            offsetSeconds = 0
        case let offset?:
            let digits = offset.dropFirst().filter(\.isNumber)
            guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
            let seconds = (hours * 60 + minutes) * 60
            offsetSeconds = offset.hasPrefix("-") ? -seconds : seconds
        }
    }

    /// Milliseconds since the epoch when the fields are read as wall time in `zone`:
    /// by arithmetic (`CivilTime`), or with a `Calendar` for what it can't be sure
    /// of (a field out of range, a year before 1600, a time near a daylight saving
    /// change).
    func milliseconds(in zone: TimeZone) -> Int64? {
        let millis = Int64((fraction ?? "").prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        if let seconds = fastSeconds(in: zone) { return seconds * 1000 + millis }
        return calendarMilliseconds(in: zone)
    }

    private func fastSeconds(in zone: TimeZone) -> Int64? {
        guard let year = fields.year, let month = fields.month, let day = fields.day, let hour = fields.hour,
              let minute = fields.minute, let second = fields.second,
              CivilTime.years.contains(Int64(year)), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }
        let days = CivilTime.days(year: Int64(year), month: Int64(month), day: Int64(day))
        let naive = days * 86_400 + Int64(hour * 3600 + minute * 60 + second)
        return CivilTime.instant(ofWallTime: naive, in: zone)
    }

    /// `milliseconds(in:)` with a `Calendar`.
    func calendarMilliseconds(in zone: TimeZone) -> Int64? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: fields) else { return nil }
        let millis = Int64((fraction ?? "").prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        return Int64(date.timeIntervalSince1970.rounded()) * 1000 + millis
    }
}

extension DatetimeConversions {
    /// Every form of the instant `milliseconds` after the epoch; milliseconds show
    /// in the ISO forms only when `fractional`.
    init(milliseconds: Int64, fractional: Bool, timeZone: TimeZone, now: Date) {
        let instant = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        let offset = timeZone.secondsFromGMT(for: instant)
        let seconds = floorDivision(milliseconds, 1000)
        self.init(
            instant: instant,
            isoUTC: wallTime(milliseconds, fractional: fractional) + "Z",
            local: wallTime(milliseconds + Int64(offset) * 1000, fractional: fractional) + offsetText(offset),
            epochSeconds: String(seconds),
            epochMilliseconds: String(milliseconds),
            relative: relativeTime(
                seconds: floorDivision(Int64((now.timeIntervalSince1970 * 1000).rounded()) - milliseconds, 1000)
            )
        )
    }
}

/// `2026-10-07T04:17:10[.123]` for the UTC wall time `milliseconds` after the epoch.
func wallTime(_ milliseconds: Int64, fractional: Bool) -> String {
    let seconds = floorDivision(milliseconds, 1000)
    guard let wall = CivilTime.wallTime(seconds: seconds) else { return calendarWallTime(milliseconds, fractional: fractional) }
    var text = CivilTime.dateText(year: wall.year, month: wall.month, day: wall.day) + "T"
        + CivilTime.timeText(secondOfDay: wall.secondOfDay)
    if fractional { text += "." + CivilTime.padded(milliseconds - seconds * 1000, 3) }
    return text
}

/// `wallTime` with a `Calendar`, for years `CivilTime` doesn't cover.
func calendarWallTime(_ milliseconds: Int64, fractional: Bool) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let seconds = floorDivision(milliseconds, 1000)
    let parts = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: Double(seconds))
    )
    var text = String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!
    )
    if fractional { text += String(format: ".%03d", Int(milliseconds - seconds * 1000)) }
    return text
}

/// `+07:00`, `-03:30`, `+00:00`.
private func offsetText(_ seconds: Int) -> String {
    let minutes = Int64(abs(seconds) / 60)
    return (seconds < 0 ? "-" : "+") + CivilTime.padded(minutes / 60, 2) + ":" + CivilTime.padded(minutes % 60, 2)
}

/// English, rounded down to the largest whole unit: "just now" under a minute,
/// then "5 minutes ago" or "in 3 hours", up to years. `seconds` is positive for
/// the past.
private func relativeTime(seconds: Int64) -> String {
    let units: [(String, Int64)] = [
        ("year", 365 * 86_400), ("month", 30 * 86_400), ("day", 86_400), ("hour", 3_600), ("minute", 60),
    ]
    let magnitude = abs(seconds)
    guard let (name, size) = units.first(where: { magnitude >= $0.1 }) else { return "just now" }
    let count = magnitude / size
    let amount = "\(count) \(name)\(count == 1 ? "" : "s")"
    return seconds > 0 ? amount + " ago" : "in " + amount
}

