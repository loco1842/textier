import Foundation

/// Everything the Inspector shows for one Input: the top-level Matches (which the
/// Panel highlights), one tab per Pattern that matched, the Plain Text tab, and
/// the selected entry.
public struct Inspection: Sendable, Equatable {
    /// The top-level Matches, ordered by position, as `detect` returns them.
    public var matches: [Match]
    /// Pattern tabs in display order, then the Plain Text tab when it has entries.
    public var tabs: [InspectorTab]
    /// The selected entry; the app writes the user's choice back here so the next
    /// `inspect(previous:)` keeps it.
    public var selection: EntryID?
    /// The Patterns stopped for taking longer than the time limit on this Input, so
    /// some of their Matches may be missing; by name, in the order they were
    /// stopped (Config order, unless one ran out on a Field value).
    public var slowPatterns: [String]

    public init(matches: [Match], tabs: [InspectorTab], selection: EntryID?, slowPatterns: [String] = []) {
        self.matches = matches
        self.tabs = tabs
        self.selection = selection
        self.slowPatterns = slowPatterns
    }

    /// The Inspector is shown only when at least one Pattern tab exists.
    public var showsInspector: Bool {
        tabs.contains { $0.id != .plainText }
    }

    public func tab(_ id: InspectorTab.ID) -> InspectorTab? {
        tabs.first { $0.id == id }
    }

    public func entry(_ id: EntryID) -> InspectorEntry? {
        tab(id.tab).flatMap { $0.entries.indices.contains(id.index) ? $0.entries[id.index] : nil }
    }

    public var selectedEntry: InspectorEntry? {
        selection.flatMap(entry)
    }

    /// The entry for a top-level Match, which is where a double-click on it in the
    /// Input lands.
    public func entryID(for match: Match) -> EntryID? {
        let id = InspectorTab.ID.pattern(match.patternName)
        guard let tab = tab(id), let index = tab.entries.firstIndex(where: { $0.range == match.range }) else {
            return nil
        }
        return EntryID(tab: id, index: index)
    }
}

/// Which entry: its tab, and its index within that tab.
public struct EntryID: Sendable, Equatable, Hashable {
    public var tab: InspectorTab.ID
    public var index: Int

    public init(tab: InspectorTab.ID, index: Int) {
        self.tab = tab
        self.index = index
    }
}

/// One Inspector tab: a Pattern's Matches, or the Plain Text entries.
public struct InspectorTab: Sendable, Equatable, Identifiable {
    public enum ID: Sendable, Equatable, Hashable {
        /// A Pattern's tab, by Pattern name.
        case pattern(String)
        case plainText
    }

    public var id: ID
    /// The Pattern's name, or "Plain Text".
    public var title: String
    /// The Pattern's resolved color; nil for Plain Text.
    public var color: PatternColor?
    /// The Pattern name's Glyph, or Plain Text's.
    public var glyph: Glyph
    /// Ordered by position in the Input.
    public var entries: [InspectorEntry]

    public init(id: ID, title: String, color: PatternColor?, glyph: Glyph, entries: [InspectorEntry]) {
        self.id = id
        self.title = title
        self.color = color
        self.glyph = glyph
        self.entries = entries
    }
}

/// One row of an Inspector tab: a Match (top-level or nested) or a Plain Text piece.
public struct InspectorEntry: Sendable, Equatable {
    /// The index within its tab, from 0.
    public var index: Int
    /// One line: whitespace runs collapsed to a space, truncated with "…".
    public var preview: String
    /// UTF-16 range in the Input.
    public var range: NSRange
    /// The entry's text as it appears in the Input (trimmed, for Plain Text).
    public var text: String
    /// The Pattern's Actions; `[.copy]` for Plain Text.
    public var actions: [Action]
    /// The top-level Match a nested Match sits in; nil for top-level Matches and
    /// Plain Text.
    public var parent: ParentTag?
    /// The Match's Fields, shown above `detail`; none for Plain Text.
    public var fields: [FieldEntry]
    public var detail: Detail
    /// What the Match means in one line, from `detail` or `fields`; nil when that
    /// would only repeat its text, and for Plain Text.
    public var summary: Summary?
    /// The Match's color: its Pattern's, or a Color Rule's; nil for Plain Text.
    public var color: PatternColor?

    public init(
        index: Int, preview: String, range: NSRange, text: String, actions: [Action], parent: ParentTag?,
        fields: [FieldEntry] = [], detail: Detail, summary: Summary? = nil, color: PatternColor? = nil
    ) {
        self.index = index
        self.preview = preview
        self.range = range
        self.text = text
        self.actions = actions
        self.parent = parent
        self.fields = fields
        self.detail = detail
        self.summary = summary
        self.color = color
    }
}

/// A Field as the Inspector shows it: a row that copies its value, and the
/// Actions of the URL or file path Match its value is in its entirety.
public struct FieldEntry: Sendable, Equatable {
    public var field: Field
    /// The Match the whole value is, per `stringValueMatch`; nil for other values.
    public var link: Match?

    public init(field: Field, link: Match? = nil) {
        self.field = field
        self.link = link
    }
}

/// Where a nested Match came from: the Pattern and index (within its tab) of the
/// enclosing top-level Match.
public struct ParentTag: Sendable, Equatable {
    public var patternName: String
    public var index: Int

    public init(patternName: String, index: Int) {
        self.patternName = patternName
        self.index = index
    }

    /// "in json 0".
    public var description: String { "in \(patternName) \(index)" }
}

/// An entry parsed for display.
public enum Detail: Sendable, Equatable {
    case json(JSONValue)
    case url(URLDetail)
    case datetime(DatetimeDetail)
    case filePath(FilePathDetail)
    case text(String)
}

/// A URL broken into its parts.
public struct URLDetail: Sendable, Equatable {
    public var scheme: String
    public var host: String
    public var port: Int?
    public var path: String
    /// In order, percent-decoded, repeated names kept.
    public var query: [QueryParameter]
    public var fragment: String?

    public init(
        scheme: String, host: String, port: Int? = nil, path: String, query: [QueryParameter] = [],
        fragment: String? = nil
    ) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.fragment = fragment
    }
}

public struct QueryParameter: Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A datetime converted into the common forms.
public struct DatetimeDetail: Sendable, Equatable {
    /// Whether the text had no offset, so it was read as local time.
    public var assumedLocal: Bool
    /// The conversions as read: with the text's own offset, or local time when it has none.
    public var conversions: DatetimeConversions
    /// The conversions when an offset-less datetime is read as UTC instead; nil when
    /// the text has an offset or is an epoch.
    public var asUTC: DatetimeConversions?

    public init(assumedLocal: Bool, conversions: DatetimeConversions, asUTC: DatetimeConversions?) {
        self.assumedLocal = assumedLocal
        self.conversions = conversions
        self.asUTC = asUTC
    }
}

/// One instant in every form the Inspector shows.
public struct DatetimeConversions: Sendable, Equatable {
    public var instant: Date
    /// `2026-10-07T04:17:10Z` (fractional seconds kept when the text had them).
    public var isoUTC: String
    /// `2026-10-07T11:17:10+07:00`, in the time zone passed to `inspect`.
    public var local: String
    public var epochSeconds: String
    public var epochMilliseconds: String
    /// Relative to `now`: "2 days ago", "in 3 hours", "just now".
    public var relative: String

    public init(
        instant: Date, isoUTC: String, local: String, epochSeconds: String, epochMilliseconds: String,
        relative: String
    ) {
        self.instant = instant
        self.isoUTC = isoUTC
        self.local = local
        self.epochSeconds = epochSeconds
        self.epochMilliseconds = epochMilliseconds
        self.relative = relative
    }
}

/// A file path Match's location, and whether it's on this machine.
public struct FilePathDetail: Sendable, Equatable {
    /// Where a file path's line came from.
    public enum LineSource: Sendable, Equatable {
        /// The path's own `:line` suffix.
        case path
        /// The sibling `line` key of the JSON object the path is the `file` of.
        case lineKey
    }

    /// With `~/` expanded.
    public var path: String
    public var line: Int?
    public var column: Int?
    public var exists: Bool
    /// Nil when there's no line.
    public var lineSource: LineSource?

    /// `lineSource` defaults to the path's own suffix when there's a line.
    public init(path: String, line: Int?, column: Int?, exists: Bool, lineSource: LineSource? = nil) {
        self.path = path
        self.line = line
        self.column = column
        self.exists = exists
        self.lineSource = line == nil ? nil : lineSource ?? .path
    }
}

/// Inspects `input`: detects its Matches and lays out the Inspector.
///
/// Without `previous`, tabs are ordered by the position of each Pattern's first
/// Match (nested Matches at their own position) and the largest top-level Match is
/// selected. With `previous`, its tabs keep their order, new tabs are appended
/// before Plain Text, empty tabs are dropped, and the selection moves to the Match
/// of the same Pattern nearest the old selection, or else the largest top-level
/// Match. A file path that's the `file` of a JSON object in a `json` Match takes the
/// object's `line` (`fileLineTargets(in:config:)`) and previews as `path:line`.
/// `fileExists` is asked about each file path (after `~/` expansion against
/// `homeDirectory`), so tests never touch the disk. A Pattern still matching after
/// `timeLimit` (`Pattern.timeLimit`, shorter in tests), over all its passes in this
/// inspection, is stopped and named in `slowPatterns`.
///
/// Once `isCancelled` returns true, inspecting stops early, and what it returns is
/// incomplete and meant to be dropped.
public func inspect(
    _ input: String, config: Config, previous: Inspection? = nil, now: Date, timeZone: TimeZone,
    homeDirectory: String = NSHomeDirectory(), timeLimit: Duration = Pattern.timeLimit,
    isCancelled: @escaping @Sendable () -> Bool = { false }, fileExists: @Sendable (String) -> Bool
) -> Inspection {
    let budget = MatchingBudget(timeLimit: timeLimit, isCancelled: isCancelled)
    // A cancelled inspection's result is never used: it stops at the next check.
    let cancelled = Inspection(matches: [], tabs: [], selection: nil)
    let matches = detect(input, config: config, budget: budget)
    if budget.isCancelled() { return cancelled }
    let parser = DetailParser(config: config, now: now, timeZone: timeZone, homeDirectory: homeDirectory)
    let linesByRange = pairedLines(in: matches, config: config, budget: budget)
    if budget.isCancelled() { return cancelled }

    // Pre-order is position order: a Match starts no later than its children, and
    // siblings follow one another. Tabs are created in first-appearance order.
    // First each Match's place (its tab, its index there, its parent's tag) in that
    // order; then what each one costs to work out (its detail, preview and
    // Summary), on every core; then the entries, with their Fields' links, whose
    // matching shares the time limit's budget.
    var tabs: [InspectorTab] = []
    var tabIndex: [InspectorTab.ID: Int] = [:]
    var tabCounts: [Int] = []
    var slots: [EntrySlot] = []
    func place(_ match: Match, parent: ParentTag?) -> ParentTag {
        let id = InspectorTab.ID.pattern(match.patternName)
        let tab = tabIndex[id] ?? {
            tabs.append(InspectorTab(
                id: id, title: match.patternName, color: config.color(ofName: match.patternName),
                glyph: config.glyph(ofName: match.patternName),
                entries: []
            ))
            tabIndex[id] = tabs.count - 1
            tabCounts.append(0)
            return tabs.count - 1
        }()
        let index = tabCounts[tab]
        tabCounts[tab] += 1
        slots.append(EntrySlot(match: match, parent: parent, tab: tab, index: index))
        return ParentTag(patternName: match.patternName, index: index)
    }
    func placeNested(_ children: [Match], in topLevel: ParentTag) {
        for child in children {
            _ = place(child, parent: topLevel)
            placeNested(child.children, in: topLevel)
        }
    }
    for (position, match) in matches.enumerated() {
        if position % 256 == 255, budget.isCancelled() { return cancelled }
        placeNested(match.children, in: place(match, parent: nil))
    }

    let parsed = slots.concurrentMap { slot -> ParsedEntry in
        let match = slot.match
        let detail = parser.detail(of: match, pairedLine: linesByRange[match.range], fileExists: fileExists)
        let preview = if case .filePath(let file) = detail, file.lineSource == .lineKey, let line = file.line {
            preview(of: "\(match.text):\(line)", keepingEnd: true)
        } else {
            preview(of: match.text)
        }
        let summary = summary(of: detail, fields: match.fields, text: match.text, now: now, timeZone: timeZone)
        return ParsedEntry(detail: detail, preview: preview, summary: summary)
    }
    if budget.isCancelled() { return cancelled }

    for (slot, parsed) in zip(slots, parsed) {
        let match = slot.match
        let fields = match.fields.map {
            FieldEntry(field: $0, link: stringValueMatch($0.value, config: config, budget: budget))
        }
        tabs[slot.tab].entries.append(InspectorEntry(
            index: slot.index, preview: parsed.preview, range: match.range, text: match.text, actions: match.actions,
            parent: slot.parent, fields: fields, detail: parsed.detail, summary: parsed.summary, color: match.color
        ))
    }

    if let previous {
        tabs = keepingOrder(of: previous, tabs)
    }
    let plainText = plainTextEntries(in: input, between: matches)
    if !plainText.isEmpty {
        tabs.append(InspectorTab(id: .plainText, title: "Plain Text", color: nil, glyph: .plainText, entries: plainText))
    }

    var inspection = Inspection(matches: matches, tabs: tabs, selection: nil, slowPatterns: budget.stopped)
    inspection.selection = inspection.selection(keeping: previous)
    return inspection
}

/// A Match's place among the entries: its tab, its index there, and the top-level
/// Match it's nested in.
private struct EntrySlot: Sendable {
    var match: Match
    var parent: ParentTag?
    var tab: Int
    var index: Int
}

/// What an entry costs to work out from its Match.
private struct ParsedEntry: Sendable {
    var detail: Detail
    var preview: String
    var summary: Summary?
}

extension InspectorEntry {
    /// Previews longer than this many characters are cut, ending in "…".
    public static let previewLength = 80

    /// `text` previewed as an entry's: on one line, cut to `previewLength`.
    public static func preview(of text: String) -> String {
        TextierCore.preview(of: text)
    }

    /// Tooltips stop after this many lines or characters, ending in "…".
    public static let tooltipLines = 10
    public static let tooltipLength = 300

    /// The row's tooltip: the start of the text, up to `tooltipLines` lines and
    /// `tooltipLength` characters. Only that much of `text` is read, so a whole
    /// JSON document or a multi-MB gap of Plain Text costs no more than a line.
    public var tooltip: String {
        var end = text.startIndex
        var characters = 0
        var lines = 1
        while end < text.endIndex, characters < Self.tooltipLength {
            if text[end].isNewline {
                guard lines < Self.tooltipLines else { break }
                lines += 1
            }
            end = text.index(after: end)
            characters += 1
        }
        return end == text.endIndex ? text : text[..<end] + "…"
    }
}

/// `text` on one line: whitespace runs collapsed to one space, trimmed, and cut to
/// `InspectorEntry.previewLength` characters, at the end or, `keepingEnd`, at the
/// front (a paired path keeps its file name and line).
private func preview(of text: String, keepingEnd: Bool = false) -> String {
    let words = text.split { $0.isWhitespace }
    let line = words.joined(separator: " ")
    guard line.count > InspectorEntry.previewLength else { return line }
    let kept = InspectorEntry.previewLength - 1
    return keepingEnd ? "…" + line.suffix(kept) : line.prefix(kept) + "…"
}

/// The lines paired with `file` values, by their UTF-16 range in the Input: the
/// pairing rule's textual form run over every `json` Match, at any depth.
private func pairedLines(in matches: [Match], config: Config, budget: MatchingBudget) -> [NSRange: Int] {
    var lines: [NSRange: Int] = [:]
    func visit(_ match: Match) {
        if config.pattern(of: match)?.kind == .builtin(.json) {
            for target in fileLineTargets(in: match.text, config: config, budget: budget) {
                lines[NSRange(location: match.range.location + target.range.location, length: target.range.length)] = target.line
            }
        }
        match.children.forEach(visit)
    }
    matches.forEach(visit)
    return lines
}

private extension [Match] {
    /// The longest Match, the first of equals.
    var largest: Match? {
        reduce(nil) { best, match in
            guard let best else { return match }
            return match.range.length > best.range.length ? match : best
        }
    }
}

// MARK: Steadiness while editing

/// Pattern tabs in `previous`'s order where they still exist, then new ones in
/// first-appearance order. Tabs with no entries were never created, so dropping is
/// the filter.
private func keepingOrder(of previous: Inspection, _ tabs: [InspectorTab]) -> [InspectorTab] {
    let kept = previous.tabs.compactMap { old in tabs.first { $0.id == old.id } }
    let added = tabs.filter { tab in !previous.tabs.contains { $0.id == tab.id } }
    return kept + added
}

extension Inspection {
    /// The selection `inspect(previous:)` gives this Inspection: the entry of
    /// `previous`'s selected tab nearest its selected range, or else the largest
    /// top-level Match's. For a selection made in `previous` after this Inspection
    /// was started from an earlier one.
    public func selection(keeping previous: Inspection?) -> EntryID? {
        previous.flatMap { nearestToSelection(of: $0, in: self) } ?? matches.largest.flatMap(entryID(for:))
    }
}

/// The entry in the previously selected tab nearest the previously selected range,
/// or nil when there was no selection or that tab is gone.
private func nearestToSelection(of previous: Inspection, in inspection: Inspection) -> EntryID? {
    guard let selection = previous.selection, let old = previous.entry(selection),
          let tab = inspection.tab(selection.tab)
    else { return nil }
    let nearest = tab.entries.min { distance($0.range, old.range) < distance($1.range, old.range) }
    return nearest.map { EntryID(tab: tab.id, index: $0.index) }
}

/// How far `range` is from `old`, for "nearest": the gap between them (0 when they
/// overlap), then more overlap first, then how far their starts are apart.
private func distance(_ range: NSRange, _ old: NSRange) -> (Int, Int, Int) {
    let overlap = NSIntersectionRange(range, old).length
    let gap = max(0, max(range.location, old.location) - min(NSMaxRange(range), NSMaxRange(old)))
    return (gap, -overlap, abs(range.location - old.location))
}

// MARK: Plain Text

/// The gaps between top-level Matches, each trimmed of whitespace, of closing
/// brackets and separators at its start and of opening brackets and separators at
/// its end (they belong to the Matches around it), and dropped when nothing but
/// whitespace, punctuation and symbols is left.
private func plainTextEntries(in input: String, between matches: [Match]) -> [InspectorEntry] {
    let text = input as NSString
    var gaps: [NSRange] = []
    var start = 0
    for match in matches {
        gaps.append(NSRange(location: start, length: match.range.location - start))
        start = NSMaxRange(match.range)
    }
    gaps.append(NSRange(location: start, length: text.length - start))

    // Each gap trimmed, read and previewed on every core; the text is only read.
    nonisolated(unsafe) let shared = text
    let pieces = gaps.concurrentMap { gap -> (range: NSRange, text: String, preview: String)? in
        let range = trimmed(gap, in: shared)
        guard range.length > 0 else { return nil }
        let piece = shared.substring(with: range)
        guard piece.unicodeScalars.contains(where: { !ignorable.contains($0) }) else { return nil }
        return (range, piece, preview(of: piece))
    }
    var entries: [InspectorEntry] = []
    for case let piece? in pieces {
        entries.append(InspectorEntry(
            index: entries.count, preview: piece.preview, range: piece.range, text: piece.text, actions: [.copy],
            parent: nil, detail: .text(piece.text)
        ))
    }
    return entries
}

private let ignorable = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
private let leadingTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ")]}>,;:"))
private let trailingTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "([{<,;:"))

private func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
    var start = range.location
    var end = NSMaxRange(range)
    func scalar(at index: Int) -> Unicode.Scalar? { Unicode.Scalar(text.character(at: index)) }
    while start < end, let scalar = scalar(at: start), leadingTrim.contains(scalar) { start += 1 }
    while end > start, let scalar = scalar(at: end - 1), trailingTrim.contains(scalar) { end -= 1 }
    return NSRange(location: start, length: end - start)
}
