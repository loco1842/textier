import Foundation

extension Pattern {
    /// How long one Pattern may spend matching in one inspection, across all its
    /// `detect` passes (the Input's, each Field value's, each paired `file`'s),
    /// before it's stopped, so a regex that backtracks catastrophically can't hang
    /// the app. A shipped Pattern takes a fraction of this over a few MB of logs.
    public static let timeLimit: Duration = .seconds(2)
}

/// Detects the top-level Matches in `input`, ordered by position.
///
/// Candidates come from every enabled Pattern. When two overlap without one
/// containing the other, the longer wins, tie broken by Pattern order in
/// `config`; identical ranges keep only the earlier Pattern's. A Match inside
/// another becomes its child, recursively, unless both Patterns share a name: one
/// group doesn't nest in itself, so the inner one is dropped (`3` in `3.14`).
///
/// A regex Pattern still matching after `Pattern.timeLimit` is stopped and keeps
/// the Matches it found by then.
public func detect(_ input: String, config: Config) -> [Match] {
    detect(input, config: config, including: { _ in true })
}

/// `detect` with only the enabled Patterns `include` accepts, so Matches keep
/// their Pattern's index in `config`.
func detect(_ input: String, config: Config, including include: (Pattern) -> Bool) -> [Match] {
    detect(input, config: config, budget: MatchingBudget(), including: include)
}

/// What the `detect` passes of one inspection may spend: each Pattern's
/// `timeLimit`, shared by all its passes, and nothing more once `isCancelled`
/// says so. Every pass of one budget takes the same Config.
final class MatchingBudget {
    let timeLimit: Duration
    let isCancelled: @Sendable () -> Bool
    /// The Patterns stopped for taking longer than `timeLimit`, by name, once
    /// each, in the order they were stopped.
    private(set) var stopped: [String] = []
    /// The time each Pattern has spent matching, by its index in the Config.
    private var spent: [Int: Duration] = [:]

    init(timeLimit: Duration = Pattern.timeLimit, isCancelled: @escaping @Sendable () -> Bool = { false }) {
        self.timeLimit = timeLimit
        self.isCancelled = isCancelled
    }

    /// What's left of the Pattern at `order`'s time.
    func remaining(_ order: Int) -> Duration {
        timeLimit - spent[order, default: .zero]
    }

    /// Records a pass of the Pattern at `order` that took `elapsed`, and whether it
    /// was stopped for running out of time.
    /// A Pattern whose time is used up counts as stopped too, as it won't run again
    /// in this inspection, though no one pass of it ran long enough to be cut off.
    func record(_ order: Int, name: String, elapsed: Duration, stopped wasStopped: Bool) {
        spent[order, default: .zero] += elapsed
        if wasStopped || remaining(order) <= .zero, !stopped.contains(name) { stopped.append(name) }
    }
}

/// `detect`, each Pattern matching only for what's left of its time in `budget`,
/// which notes those it stopped. Once the budget is cancelled, no more Patterns
/// run and the Matches are incomplete.
func detect(
    _ input: String, config: Config, budget: MatchingBudget, including include: (Pattern) -> Bool = { _ in true }
) -> [Match] {
    var candidates: [Candidate] = []
    for (order, pattern) in config.patterns.enumerated() where pattern.enabled && include(pattern) {
        if budget.isCancelled() { return [] }
        let found = matches(of: pattern, at: order, in: input, grok: config.grok, budget: budget)
        for match in found where match.range.length > 0 {
            candidates.append(Candidate(range: match.range, order: order, pattern: pattern, fields: match.fields))
        }
    }
    // Nothing found is the usual answer for a Field value (`stringValueMatch`), so
    // it skips the colors.
    guard !candidates.isEmpty else { return [] }
    // Outer before inner at the same location, so each container precedes what it contains.
    let ordered = resolveOverlaps(candidates).sorted {
        ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length)
    }
    // The Color Rules of each Pattern that ran (none for the rest), by Config order.
    let rules = config.patterns.map { pattern in
        guard pattern.enabled && include(pattern) else { return [(NSRegularExpression, PatternColor)]() }
        return pattern.effectiveColorRules.compactMap { rule in rule.regex(grok: config.grok).map { ($0, rule.color) } }
    }
    return nest(ordered[...], in: input as NSString, colors: config.resolvedColors, rules: rules)
}

/// `stringValueMatch` within `budget`: the Match `string` is in its entirety, of a
/// regex Pattern that opens a URL or a file. Keep its Patterns in step with
/// `stringValueMatch`'s.
func stringValueMatch(_ string: String, config: Config, budget: MatchingBudget) -> Match? {
    let whole = NSRange(string.startIndex..., in: string)
    return detect(string, config: config, budget: budget) {
        guard case .regex = $0.kind else { return false }
        return $0.actions.contains(.openURL) || $0.actions.contains(.openFile)
    }.first { $0.range == whole }
}

private struct Candidate {
    var range: NSRange
    /// The Pattern's position in the Config, for tie-breaks.
    var order: Int
    var pattern: Pattern
    var fields: [Field]
}

/// Where `pattern`, at `order` in the Config, matches `input`, with each Match's
/// Fields: those found before its time in `budget` ran out (it's then noted as
/// stopped) or the budget was cancelled.
private func matches(
    of pattern: Pattern, at order: Int, in input: String, grok: [GrokDefinition], budget: MatchingBudget
) -> [(range: NSRange, fields: [Field])] {
    switch pattern.kind {
    case .regex(let source):
        // Stopped in an earlier pass of this inspection: it isn't run again.
        let remaining = budget.remaining(order)
        guard remaining > .zero, case .success(let compiled) = compileRegex(source, grok: grok) else { return [] }
        let text = input as NSString
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: remaining)
        var found: [(range: NSRange, fields: [Field])] = []
        var stopped = false
        var calls = 0
        // With `reportProgress`, ICU also calls back every so often during one long
        // match attempt, not only between Matches, so a runaway regex is stopped too.
        // It calls back at every position it tries, millions of times over a few MB,
        // so the clock is read only every 256th time: reading it each time would
        // make a shipped Pattern several times slower. A runaway regex calls back
        // a few thousand times a second, so it's still stopped within a moment.
        compiled.regex.enumerateMatches(
            in: input, options: .reportProgress, range: NSRange(location: 0, length: text.length)
        ) { result, _, stop in
            if let result {
                let fields = compiled.fields.compactMap { field -> Field? in
                    let range = result.range(withName: field.group)
                    guard range.location != NSNotFound else { return nil }
                    return Field(name: field.name, type: field.type, value: text.substring(with: range), range: range)
                }
                found.append((result.range, fields))
            }
            calls &+= 1
            guard calls % 256 == 0 else { return }
            if clock.now >= deadline {
                stopped = true
                stop.pointee = true
            } else if budget.isCancelled() {
                stop.pointee = true
            }
        }
        budget.record(order, name: pattern.name, elapsed: start.duration(to: clock.now), stopped: stopped)
        return found
    case .builtin(.json):
        return jsonRanges(in: input).map { ($0, []) }
    case .builtin(.escapedJSON):
        // Applies to JSON string values in the JSON Viewer, not to the Input (ticket 08).
        return []
    }
}

/// Keeps the candidates that survive the overlap rule. Taking candidates longest
/// first, then by Config order, means each one only has to be checked against
/// those already kept: any it partially overlaps (or duplicates) outranks it.
private func resolveOverlaps(_ candidates: [Candidate]) -> [Candidate] {
    let ranked = candidates.indices.sorted { a, b in
        let (x, y) = (candidates[a], candidates[b])
        return (x.range.length, -x.order, -x.range.location) > (y.range.length, -y.order, -y.range.location)
    }
    var names: [String: Int] = [:]
    let extent = candidates.map { NSMaxRange($0.range) }.max() ?? 0
    var kept = KeptRanges(extent: extent)
    return ranked.compactMap { index in
        let candidate = candidates[index]
        let name = names[candidate.pattern.name, default: names.count]
        names[candidate.pattern.name] = name
        return kept.keep(candidate.range, name: name) ? candidate : nil
    }
}

/// The ranges kept so far, which never partially overlap: any two are disjoint or
/// one contains the other. Since they come longest first, a new range can only be
/// contained by kept ones, never contain one, so checking it takes its neighbours
/// by location and the chain of kept ranges containing it, not every kept range.
private struct KeptRanges {
    private var ranges: [NSRange] = []
    private var names: [Int] = []
    /// The innermost kept range containing each, when it was kept (later ones are
    /// shorter, so it never changes).
    private var parents: [Int?] = []
    /// Indices into `ranges`, by location in buckets of `width` characters; within
    /// one location, outer before inner.
    private var buckets: [[Int]]
    private static let width = 2048

    init(extent: Int) {
        buckets = Array(repeating: [], count: extent / Self.width + 1)
    }

    /// Keeps `range` (of the Pattern name numbered `name`) unless it partially
    /// overlaps or duplicates a kept range, or sits inside one of the same name.
    mutating func keep(_ range: NSRange, name: Int) -> Bool {
        let bucket = range.location / Self.width
        let slots = buckets[bucket]
        // Where it goes: after every kept range starting at or before it.
        var low = 0, high = slots.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[slots[middle]].location <= range.location { low = middle + 1 } else { high = middle }
        }
        let insertion = low

        // A kept range starting inside it is no shorter, so it overlaps it partially.
        if let next = insertion < slots.count ? slots[insertion] : firstKept(after: bucket),
           ranges[next].location < NSMaxRange(range) {
            return false
        }

        // The innermost kept range containing it, if any.
        var container: Int?
        if insertion > 0, ranges[slots[insertion - 1]].location == range.location {
            // The innermost one starting where it does; no shorter, so it contains it
            // unless it's the same range.
            let same = slots[insertion - 1]
            if ranges[same].length == range.length { return false }
            container = same
        } else {
            // A kept range covering its start is the last one before it or contains
            // that one, so climb from there.
            var node = insertion > 0 ? slots[insertion - 1] : lastKept(before: bucket)
            while let current = node, NSMaxRange(ranges[current]) <= range.location {
                node = parents[current]
            }
            if let covering = node {
                if NSMaxRange(ranges[covering]) < NSMaxRange(range) { return false }
                container = covering
            }
        }
        // One group doesn't nest in itself.
        var ancestor = container
        while let current = ancestor {
            if names[current] == name { return false }
            ancestor = parents[current]
        }

        ranges.append(range)
        names.append(name)
        parents.append(container)
        buckets[bucket].insert(ranges.count - 1, at: insertion)
        return true
    }

    private func firstKept(after bucket: Int) -> Int? {
        buckets[(bucket + 1)...].first { !$0.isEmpty }?.first
    }

    private func lastKept(before bucket: Int) -> Int? {
        buckets[..<bucket].last { !$0.isEmpty }?.last
    }
}

/// Builds the Match tree from position-ordered candidates with no partial overlaps:
/// each candidate's children are the run of candidates after it that start inside
/// it (and so, with no partial overlaps, end inside it too). Each Match takes its
/// Pattern's first Color Rule that applies, or else its entry in `colors`, the
/// Config's resolved colors.
private func nest(
    _ candidates: ArraySlice<Candidate>, in input: NSString, colors: [PatternColor],
    rules: [[(NSRegularExpression, PatternColor)]]
) -> [Match] {
    var matches: [Match] = []
    var rest = candidates
    while let outer = rest.popFirst() {
        let inner = rest.prefix { $0.range.location < NSMaxRange(outer.range) }
        rest = rest.dropFirst(inner.count)
        let text = input.substring(with: outer.range)
        matches.append(Match(
            range: outer.range,
            text: text,
            patternName: outer.pattern.name,
            patternIndex: outer.order,
            actions: outer.pattern.actions,
            // A Color Rule's color, or the Pattern's.
            color: rules[outer.order].first { regex, _ in
                regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
            }?.1 ?? colors[outer.order],
            children: nest(inner, in: input, colors: colors, rules: rules),
            fields: outer.fields
        ))
    }
    return matches
}
