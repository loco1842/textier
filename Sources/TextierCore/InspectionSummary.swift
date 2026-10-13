import Foundation

/// One line saying what a Match means, taken from its parsed view. An offset-less
/// datetime has two, as its parsed view does: assumed local, and read as UTC.
public struct Summary: Sendable, Equatable {
    /// The Summary as read: a datetime with its own offset, or assumed local.
    public var text: String
    /// An offset-less datetime's Summary when it's read as UTC instead; nil otherwise.
    public var asUTC: String?

    public init(_ text: String, asUTC: String? = nil) {
        self.text = text
        self.asUTC = asUTC
    }

    /// The reading the Panel's "Read as UTC" choice picks.
    public func text(readsAsUTC: Bool) -> String {
        readsAsUTC ? asUTC ?? text : text
    }
}

/// The Summary of a Match parsed as `detail`, by the first rule that applies: a
/// datetime's local time (with its date when that isn't today) and age; a file
/// path's file name, line and column; a URL's host; a JSON object's size and first
/// keys, or an array's size; else its first three Fields as "name value". Nil when
/// none applies, or when it would only repeat `text`.
func summary(of detail: Detail, fields: [Field], text: String, now: Date, timeZone: TimeZone) -> Summary? {
    let summary: Summary? = switch detail {
    case .datetime(let datetime):
        Summary(
            datetime.conversions.summary(now: now, timeZone: timeZone),
            asUTC: datetime.asUTC?.summary(now: now, timeZone: timeZone)
        )
    case .filePath(let file):
        Summary(file.summary)
    case .url(let url):
        Summary(url.host)
    case .json(let value):
        value.summary.map { Summary($0) }
    case .text:
        fields.isEmpty
            ? nil
            : Summary(fields.prefix(3).map { "\($0.name) \($0.value)" }.joined(separator: " · "))
    }
    return summary?.text == text ? nil : summary
}

extension DatetimeConversions {
    /// `11:17:10 · 2 hours ago`, with `2026-10-07 ` first when the instant isn't
    /// on today's date in `timeZone`.
    func summary(now: Date, timeZone: TimeZone) -> String {
        // By arithmetic (`CivilTime`); with a `Calendar` outside the years it covers.
        func local(_ date: Date) -> (year: Int64, month: Int64, day: Int64, secondOfDay: Int64, dayNumber: Int64)? {
            let seconds = Int64(date.timeIntervalSince1970.rounded(.down))
            return CivilTime.wallTime(seconds: seconds + Int64(timeZone.secondsFromGMT(for: date)))
        }
        guard let wall = local(instant), let today = local(now) else { return calendarSummary(now: now, timeZone: timeZone) }
        let time = CivilTime.timeText(secondOfDay: wall.secondOfDay)
        let wallTime = wall.dayNumber == today.dayNumber
            ? time
            : CivilTime.dateText(year: wall.year, month: wall.month, day: wall.day) + " " + time
        return wallTime + " · " + relative
    }

    /// `summary` with a `Calendar`.
    func calendarSummary(now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        let time = String(format: "%02d:%02d:%02d", parts.hour!, parts.minute!, parts.second!)
        let wallTime = calendar.isDate(instant, inSameDayAs: now)
            ? time
            : String(format: "%04d-%02d-%02d ", parts.year!, parts.month!, parts.day!) + time
        return wallTime + " · " + relative
    }
}

extension FilePathDetail {
    /// `app.ts · line 142, col 17`, `app.ts · line 142` or `app.ts`.
    var summary: String {
        let name = (path as NSString).lastPathComponent
        switch (line, column) {
        case (let line?, let column?): return "\(name) · line \(line), col \(column)"
        case (let line?, nil): return "\(name) · line \(line)"
        default: return name
        }
    }
}

extension JSONValue {
    /// `6 keys · orderId, amount, currency…` or `3 items`; nil for a scalar.
    var summary: String? {
        func count(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }
        switch self {
        case .object(let entries):
            let size = count(entries.count, "key")
            guard !entries.isEmpty else { return size }
            let keys = entries.prefix(3).map(\.key).joined(separator: ", ")
            return size + " · " + keys + (entries.count > 3 ? "…" : "")
        case .array(let elements):
            return count(elements.count, "item")
        default:
            return nil
        }
    }
}
