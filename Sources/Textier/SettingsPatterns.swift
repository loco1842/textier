import Foundation
import TextierCore

/// Settings' Patterns section: the Patterns in priority order, and the editor for
/// the selected one. Patterns are addressed by their index in the Config.
extension SettingsModel {
    /// What a Pattern is, for what Settings lets the user do with it.
    enum PatternKind {
        /// Code detects it: it only turns on and off.
        case builtin
        /// It ships with textier: it can be edited and restored, not deleted.
        case preset
        case user
    }

    /// The Patterns the filter lets through, as indices in priority order.
    var visiblePatterns: [Int] {
        let filter = patternFilter.trimmingCharacters(in: .whitespaces)
        return config.patterns.indices.filter { index in
            guard !filter.isEmpty else { return true }
            let pattern = config.patterns[index]
            return pattern.name.localizedCaseInsensitiveContains(filter)
                || (pattern.regex ?? "").localizedCaseInsensitiveContains(filter)
        }
    }

    /// The first regex Pattern named like a shipped Preset is that Preset; others
    /// sharing its name are User Patterns in its group.
    func kind(ofPatternAt index: Int) -> PatternKind {
        let pattern = config.patterns[index]
        guard pattern.regex != nil else { return .builtin }
        guard Preset.all.contains(where: { $0.name == pattern.name }) else { return .user }
        return config.patterns.firstIndex { $0.name == pattern.name && $0.regex != nil } == index ? .preset : .user
    }

    /// The Pattern's name's color, as the Inspector shows it.
    func color(ofPatternAt index: Int) -> PatternColor {
        config.resolvedColors[index]
    }

    /// The name field: the draft while there is one, else the file's.
    func nameText(at index: Int) -> String {
        drafts[.patternName(index)]?.text ?? config.patterns[index].name
    }

    /// The regex field: the draft while there is one, else the file's.
    func regexText(at index: Int) -> String {
        drafts[.patternRegex(index)]?.text ?? config.patterns[index].regex ?? ""
    }

    /// The Grok Definitions Pattern regexes are checked against: the file's, broken
    /// ones too, as loading checks them, so Settings never writes a Pattern the next
    /// load would skip.
    var grokForPatterns: [GrokDefinition] {
        store.grokAsWritten
    }

    // MARK: The list

    /// Moves Patterns to before `destination`, as a drag in the list does,
    /// changing which wins an overlap. Drafts and the selection move with them.
    func movePatterns(from source: IndexSet, to destination: Int) {
        commitEditedRegex()
        var order = Array(config.patterns.indices)
        order.move(fromOffsets: source, toOffset: destination)
        guard order != Array(config.patterns.indices) else { return }
        let newIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        guard apply({ config in config.patterns = order.map { config.patterns[$0] } }) else { return }
        renumberPatterns { newIndex[$0] }
    }

    func setPatternEnabled(_ enabled: Bool, at index: Int) {
        apply { $0.patterns[index].enabled = enabled }
    }

    /// Adds a User Pattern at the end, and opens it in the editor. Its regex is an
    /// example to replace: ICU has no empty regex.
    func addPattern() {
        commitEditedRegex()
        let names = Set(config.patterns.map(\.name))
        let name = (1...).lazy.map { $0 == 1 ? "new pattern" : "new pattern \($0)" }.first { !names.contains($0) }!
        let pattern = Pattern(name: name, regex: #"\bTODO\b"#, actions: [.copy])
        guard apply({ $0.patterns.append(pattern) }), config.patterns.last == pattern else { return }
        selectedPattern = config.patterns.count - 1
    }

    /// Deletes a User Pattern; Presets and Built-in Patterns stay.
    func deletePattern(at index: Int) {
        guard kind(ofPatternAt: index) == .user else { return }
        // Another Pattern's regex being typed is saved first. The selected one's goes
        // with its Pattern once deleted (renumbering clears the selection), and stays
        // in the field when the file can't be written.
        if index != selectedPattern { commitEditedRegex() }
        guard apply({ $0.patterns.remove(at: index) }) else { return }
        renumberPatterns { $0 == index ? nil : $0 > index ? $0 - 1 : $0 }
    }

    /// Copies a Preset or User Pattern into a User Pattern right after it, named
    /// "… copy", and opens it in the editor.
    func duplicatePattern(at index: Int) {
        guard kind(ofPatternAt: index) != .builtin else { return }
        // The copy carries the regex as typed, not the one in the file.
        commitEditedRegex()
        var copy = config.patterns[index]
        copy.name += " copy"
        guard apply({ $0.patterns.insert(copy, at: index + 1) }) else { return }
        renumberPatterns { $0 > index ? $0 + 1 : $0 }
        selectedPattern = index + 1
    }

    // MARK: The test box

    /// What the test box's Matches depend on: the last run is reused while it's
    /// the same.
    struct TestRun: Equatable {
        var pattern: Pattern
        var input: String
        var grokForPatterns: [GrokDefinition]
        var grok: [GrokDefinition]
    }

    /// The most the test box starts with: the Panel's Input up to the last line
    /// break within this many characters, since it runs on every keystroke.
    static let testSampleLimit = 65_536

    /// The start of `input` the test box opens with, cut after a whole line when
    /// it's longer than `testSampleLimit`.
    static func testSample(of input: String) -> String {
        let head = input.prefix(testSampleLimit)
        guard head.endIndex < input.endIndex else { return input }
        return String(head.lastIndex(where: \.isNewline).map { head[...$0] } ?? head)
    }

    /// The selected Pattern with the regex as typed, run over the test box: its
    /// Matches, or why the regex doesn't compile. Nothing is written. The regex
    /// field, the test box and its Fields all ask for it on every redraw, so it
    /// runs again only when what it depends on changed.
    var testMatches: Result<[Match], RegexError> {
        guard let index = selectedPattern, config.patterns.indices.contains(index), config.patterns[index].regex != nil
        else { return .success([]) }
        // Everything observed is read before the last run is looked at, so the
        // views still redraw when it changes.
        var pattern = config.patterns[index]
        pattern.kind = .regex(editedRegex ?? regexText(at: index))
        pattern.enabled = true
        let run = TestRun(pattern: pattern, input: testInput, grokForPatterns: grokForPatterns, grok: config.grok)
        if let last = lastTestRun, last.run == run { return last.matches }
        let matches: Result<[Match], RegexError> = compileRegex(pattern.regex ?? "", grok: run.grokForPatterns).map { _ in
            detect(run.input, config: Config(patterns: [pattern], grok: run.grok))
        }
        lastTestRun = (run, matches)
        return matches
    }

    /// Whether `source` compiles as a Pattern regex against the file's definitions.
    func compiles(_ source: String) -> Bool {
        if case .success = compileRegex(source, grok: grokForPatterns) { true } else { false }
    }

    /// Selects the test box's Match at a UTF-16 location, as a click in it does.
    func selectTestMatch(at location: Int) {
        testSelection = location
    }

    /// The Fields of the test box's Match the user clicked in; none until then.
    var selectedTestFields: [Field] {
        guard let location = testSelection, case .success(let matches) = testMatches else { return [] }
        return matches.first { NSLocationInRange(location, $0.range) }?.fields ?? []
    }

    /// Writes the regex as typed, or keeps it as a draft when it doesn't compile.
    func commitEditedRegex() {
        guard let edited = editedRegex, let index = selectedPattern else { return }
        editedRegex = nil
        if edited != regexText(at: index) { setPatternRegex(edited, at: index) }
    }

    // MARK: The editor

    /// A name is needed, and `json` and `escaped-json` are the Built-in Patterns'.
    func setPatternName(_ name: String, at index: Int) {
        guard kind(ofPatternAt: index) != .builtin else { return }
        if name.isEmpty {
            keepDraft(.patternName(index), text: name, problem: "A Pattern needs a name")
        } else if BuiltinID(rawValue: name) != nil {
            keepDraft(.patternName(index), text: name, problem: "\"\(name)\" is reserved for the Built-in Pattern")
        } else {
            apply(clearing: .patternName(index), text: name) { $0.patterns[index].name = name }
        }
    }

    /// Written when it compiles against the Config's Grok Definitions; otherwise a
    /// draft with the compile step's error.
    func setPatternRegex(_ source: String, at index: Int) {
        guard kind(ofPatternAt: index) != .builtin else { return }
        if case .failure(let error) = compileRegex(source, grok: grokForPatterns) {
            keepDraft(.patternRegex(index), text: source, problem: error.message)
        } else {
            apply(clearing: .patternRegex(index), text: source) { $0.patterns[index].kind = .regex(source) }
        }
    }

    /// Turns an Action on (at the end, or first for a Pattern with none) or off.
    func setPatternAction(_ action: Action, on: Bool, at index: Int) {
        guard kind(ofPatternAt: index) != .builtin else { return }
        apply { config in
            var actions = config.patterns[index].actions.filter { $0 != action }
            if on { actions.append(action) }
            config.patterns[index].actions = actions
        }
    }

    /// Sets the Pattern's own color; nil goes back to its palette default.
    func setPatternColor(_ color: PatternColor?, at index: Int) {
        apply { $0.patterns[index].color = color }
    }

    /// Whether a Preset's regex, Actions or color differ from how it ships.
    func canRestoreDefault(at index: Int) -> Bool {
        guard let shipped = shippedPreset(at: index) else { return false }
        let pattern = config.patterns[index]
        return pattern.kind != shipped.kind || pattern.actions != shipped.actions || pattern.color != shipped.color
    }

    /// Puts back a Preset's shipped regex, Actions and color; on or off stays.
    func restoreDefault(at index: Int) {
        guard let shipped = shippedPreset(at: index) else { return }
        // The field shows the shipped regex again, rather than what was typed.
        if index == selectedPattern { editedRegex = nil }
        apply(clearing: .patternRegex(index)) { config in
            config.patterns[index].kind = shipped.kind
            config.patterns[index].actions = shipped.actions
            config.patterns[index].color = shipped.color
        }
    }

    private func shippedPreset(at index: Int) -> Pattern? {
        guard kind(ofPatternAt: index) == .preset else { return nil }
        return Preset.all.first { $0.name == config.patterns[index].name }
    }

    /// After Patterns moved: drafts and the selection follow their Pattern to its
    /// new index, or go with it.
    func renumberPatterns(_ newIndex: (Int) -> Int?) {
        var renumbered: [Setting: Draft] = [:]
        for (setting, draft) in drafts {
            switch setting {
            case .patternName(let index): newIndex(index).map { renumbered[.patternName($0)] = draft }
            case .patternRegex(let index): newIndex(index).map { renumbered[.patternRegex($0)] = draft }
            default: renumbered[setting] = draft
            }
        }
        drafts = renumbered
        selectedPattern = selectedPattern.flatMap(newIndex)
    }
}
