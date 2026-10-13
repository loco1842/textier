import Foundation
import Synchronization

extension Pattern {
    /// How long one Pattern may spend matching in one inspection of a short text,
    /// across all its `detect` passes (the Input's chunks, each Field value's, each
    /// paired `file`'s), before it's stopped, so a regex that backtracks
    /// catastrophically can't hang the app. `timeLimit(forLength:)` grows it with
    /// the text.
    public static let timeLimit: Duration = .seconds(2)

    /// The time limit for a text `length` UTF-16 units long: `timeLimit`, plus a
    /// second for each MB past 2 MB. A shipped Pattern takes about 0.06 s a MB, so
    /// only a runaway one gets near it.
    public static func timeLimit(forLength length: Int) -> Duration {
        let megabytes = Double(length) / 1_048_576
        return timeLimit + .seconds(max(0, megabytes - 2))
    }
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
func detect(_ input: String, config: Config, including include: @Sendable (Pattern) -> Bool) -> [Match] {
    let budget = MatchingBudget(timeLimit: Pattern.timeLimit(forLength: (input as NSString).length))
    return detect(input, config: config, budget: budget, including: include)
}

/// What the `detect` passes of one inspection may spend: each Pattern's
/// `timeLimit`, shared by all its passes (and the chunks of each, which run at
/// once on several cores), and nothing more once `isCancelled` says so. Every
/// pass of one budget takes the same Config.
final class MatchingBudget: Sendable {
    let timeLimit: Duration
    let isCancelled: @Sendable () -> Bool
    private struct State {
        var stopped: [String] = []
        var spent: [Int: Duration] = [:]
    }
    private let state = Mutex(State())

    init(timeLimit: Duration = Pattern.timeLimit, isCancelled: @escaping @Sendable () -> Bool = { false }) {
        self.timeLimit = timeLimit
        self.isCancelled = isCancelled
    }

    /// The Patterns stopped for taking longer than `timeLimit`, by name, once
    /// each, in the order they were stopped.
    var stopped: [String] { state.withLock { $0.stopped } }

    /// What's left of the Pattern at `order`'s time.
    func remaining(_ order: Int) -> Duration {
        timeLimit - state.withLock { $0.spent[order, default: .zero] }
    }

    /// Adds `elapsed` to the time the Pattern at `order` has spent, and returns
    /// whether it's now used up.
    func charge(_ order: Int, _ elapsed: Duration) -> Bool {
        state.withLock {
            $0.spent[order, default: .zero] += elapsed
            return $0.spent[order, default: .zero] >= timeLimit
        }
    }

    /// Notes the Pattern named `name`, at `order`, as stopped when it was cut off
    /// or its time is used up: it won't run again in this inspection, though no one
    /// pass of it ran long enough to be cut off.
    func finish(_ order: Int, name: String, stopped wasStopped: Bool) {
        state.withLock {
            let usedUp = $0.spent[order, default: .zero] >= timeLimit
            if wasStopped || usedUp, !$0.stopped.contains(name) { $0.stopped.append(name) }
        }
    }
}

/// `detect`, each Pattern matching only for what's left of its time in `budget`,
/// which notes those it stopped. Once the budget is cancelled, no more Patterns
/// run and the Matches are incomplete.
func detect(
    _ input: String, config: Config, budget: MatchingBudget, including include: (Pattern) -> Bool = { _ in true },
    chunkSize: Int? = nil, progress: @Sendable (Double) -> Void = { _ in }
) -> [Match] {
    // Each regex Pattern runs over the text's chunks, and each Built-in Pattern
    // over the whole of it, all at once on every core; then each Pattern's
    // Matches are put back in order.
    let text = input as NSString
    let chunks = lineChunks(of: text, size: chunkSize)
    var jobs: [MatchingJob] = []
    for (order, pattern) in config.patterns.enumerated() where pattern.enabled && include(pattern) {
        if case .regex = pattern.kind {
            jobs += chunks.map { MatchingJob(order: order, pattern: pattern, chunk: $0) }
        } else {
            jobs.append(MatchingJob(order: order, pattern: pattern, chunk: nil))
        }
    }
    let done = Mutex(0)
    let jobCount = jobs.count
    let found = jobs.concurrentMap(chunk: 1) { job in
        let found = budget.isCancelled()
            ? FoundMatches() : matches(of: job.pattern, at: job.order, in: input, chunk: job.chunk, grok: config.grok, budget: budget)
        let finished = done.withLock { count in
            count += 1
            return count
        }
        progress(Double(finished) / Double(jobCount))
        return found
    }
    if budget.isCancelled() { return [] }
    var candidates: [Candidate] = []
    var previous: (order: Int, end: Int)?
    for (job, found) in zip(jobs, found) {
        for match in found.matches where match.range.length > 0 {
            // A chunk's search runs a little past its end, so a Match the chunk
            // before it ended inside this one isn't followed by one starting inside it.
            if let previous, previous.order == job.order, match.range.location < previous.end { continue }
            candidates.append(Candidate(range: match.range, order: job.order, pattern: job.pattern, fields: match.fields))
            previous = (job.order, NSMaxRange(match.range))
        }
        if job.chunk == nil { previous = nil }
    }
    for (order, pattern) in config.patterns.enumerated() where pattern.enabled && include(pattern) {
        if case .regex = pattern.kind {
            let stopped = zip(jobs, found).contains { $0.order == order && $1.stopped }
            budget.finish(order, name: pattern.name, stopped: stopped)
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

/// One Pattern over one chunk of the text (nil for the whole of it).
private struct MatchingJob: Sendable {
    var order: Int
    var pattern: Pattern
    var chunk: NSRange?
}

/// How far past its end a chunk's search runs, so a Match that starts in the
/// chunk and runs on past its end is found whole.
let chunkOverlap = 4096

/// The text cut at line ends into chunks for several cores to match at once, or
/// one chunk for a text too short to be worth cutting. `size` (in UTF-16 units)
/// overrides the chunks' size, for the tests.
func lineChunks(of text: NSString, size: Int? = nil) -> [NSRange] {
    let length = text.length
    let smallest = 262_144
    guard size != nil || length >= 2 * smallest else { return [NSRange(location: 0, length: length)] }
    let size = size ?? max(smallest, length / (ProcessInfo.processInfo.activeProcessorCount * 2))
    var chunks: [NSRange] = []
    var start = 0
    while start < length {
        var end = min(start + size, length)
        // On to the next line's start, so no line is split.
        while end < length, text.character(at: end - 1) != 0x0A { end += 1 }
        chunks.append(NSRange(location: start, length: end - start))
        start = end
    }
    return chunks
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
    of pattern: Pattern, at order: Int, in input: String, chunk: NSRange?, grok: [GrokDefinition],
    budget: MatchingBudget
) -> FoundMatches {
    switch pattern.kind {
    case .regex(let source):
        // Stopped in an earlier pass of this inspection: it isn't run again.
        guard budget.remaining(order) > .zero, case .success(let compiled) = compileRegex(source, grok: grok) else {
            return FoundMatches()
        }
        let text = input as NSString
        // A chunk is searched a little past its end; only Matches starting in it are
        // kept. Its bounds are transparent and not anchors, so lookarounds, `^` and
        // `$` see the text around it, as they would searching the whole text.
        let keptEnd = chunk.map(NSMaxRange) ?? text.length
        let searched = chunk.map {
            NSRange(location: $0.location, length: min(NSMaxRange($0) + chunkOverlap, text.length) - $0.location)
        } ?? NSRange(location: 0, length: text.length)
        let clock = ContinuousClock()
        var lastCharge = clock.now
        var found = FoundMatches()
        var stopped = false
        var calls = 0
        // With `reportProgress`, ICU also calls back every so often during one long
        // match attempt, not only between Matches, so a runaway regex is stopped too.
        // It calls back at every position it tries, millions of times over a few MB,
        // so the clock is read only every 256th time: reading it each time would
        // make a shipped Pattern several times slower. A runaway regex calls back
        // a few thousand times a second, so it's still stopped within a moment.
        compiled.regex.enumerateMatches(
            in: input, options: [.reportProgress, .withTransparentBounds, .withoutAnchoringBounds], range: searched
        ) { result, _, stop in
            if let result {
                guard result.range.location < keptEnd else {
                    stop.pointee = true
                    return
                }
                let fields = compiled.fields.compactMap { field -> Field? in
                    let range = result.range(withName: field.group)
                    guard range.location != NSNotFound else { return nil }
                    return Field(name: field.name, type: field.type, value: text.substring(with: range), range: range)
                }
                found.matches.append((result.range, fields))
            }
            calls &+= 1
            guard calls % 256 == 0 else { return }
            // The time goes to the Pattern as it's spent, so its chunks running at
            // once share one limit.
            let now = clock.now
            if budget.charge(order, now - lastCharge) {
                stopped = true
                stop.pointee = true
            } else if budget.isCancelled() {
                stop.pointee = true
            }
            lastCharge = now
        }
        _ = budget.charge(order, clock.now - lastCharge)
        found.stopped = stopped
        return found
    case .builtin(.json):
        return FoundMatches(matches: jsonRanges(in: input).map { ($0, []) })
    case .builtin(.escapedJSON):
        // Applies to JSON string values in the JSON Viewer, not to the Input (ticket 08).
        return FoundMatches()
    }
}

/// What one matching pass found, and whether its Pattern was stopped in it.
private struct FoundMatches: Sendable {
    var matches: [(range: NSRange, fields: [Field])] = []
    var stopped = false
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
