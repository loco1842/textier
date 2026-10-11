import Foundation
import TextierCore

/// Settings' Grok Definitions section: the bundled library to browse, and the
/// user's own definitions, which live in the config file's `grok` object.
extension SettingsModel {
    var bundledGrok: [GrokDefinition] { GrokDefinition.bundled }

    /// The bundled definitions whose name has the filter's text.
    var visibleBundledGrok: [GrokDefinition] {
        bundledGrok.filter(matchesGrokFilter)
    }

    /// The user's definitions whose name has the filter's text.
    var visibleUserGrok: [GrokDefinition] {
        config.grok.filter(matchesGrokFilter)
    }

    private func matchesGrokFilter(_ definition: GrokDefinition) -> Bool {
        let filter = grokFilter.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || definition.name.localizedCaseInsensitiveContains(filter)
    }

    /// Whether a user definition replaces the bundled one of the same name.
    func overridesBundled(_ name: String) -> Bool {
        bundledGrok.contains { $0.name == name }
    }

    /// The regex field of a user definition: its draft while there is one.
    func grokRegexText(named name: String) -> String {
        drafts[.grokRegex(name)]?.text ?? config.grok.first { $0.name == name }?.regex ?? ""
    }

    /// Adds a definition of the user's own, or says why it can't be added.
    func addGrokDefinition(name: String, regex: String) -> String? {
        guard GrokDefinition.isValidName(name) else { return "A name is letters, digits and _ only" }
        guard !config.grok.contains(where: { $0.name == name }) else { return "\(name) is already defined; edit it below" }
        let definition = GrokDefinition(name: name, regex: regex)
        if case .failure(let error) = compileGrokDefinition(definition, grok: grokForPatterns + [definition]) {
            return error.message
        }
        apply { $0.grok.append(definition) }
        return nil
    }

    /// Written when the definition still compiles among the file's others, and the
    /// Patterns and definitions that use it still do; otherwise a draft with the
    /// compile step's error (a loop it would make, say).
    func setGrokRegex(_ regex: String, named name: String) {
        guard let index = config.grok.firstIndex(where: { $0.name == name }) else { return }
        var grok = config.grok
        grok[index].regex = regex
        let checked = Self.replacing(grok[index], in: grokForPatterns)
        if case .failure(let error) = compileGrokDefinition(grok[index], grok: checked) {
            keepDraft(.grokRegex(name), text: regex, problem: error.message)
        } else if let broken = firstBroken(by: checked, besides: [name]) {
            keepDraft(.grokRegex(name), text: regex, problem: broken)
        } else {
            apply(clearing: .grokRegex(name), text: regex) { $0.grok = grok }
        }
    }

    /// Deletes a user definition, unless a Pattern or another definition would no
    /// longer compile without it (one overriding a bundled definition falls back to
    /// it); then says which.
    func deleteGrokDefinition(named name: String) -> String? {
        let without = grokForPatterns.filter { $0.name != name }
        func breaks(_ regex: String) -> Bool {
            if case .failure = compileRegex(regex, grok: without) { true } else { false }
        }
        if let pattern = config.patterns.first(where: { $0.regex.map(breaks) ?? false }) {
            return "Pattern \"\(pattern.name)\" uses it"
        }
        if let definition = config.grok.first(where: { $0.name != name && breaks($0.regex) }) {
            return "\(definition.name) uses it"
        }
        drafts[.grokRegex(name)] = nil
        apply { $0.grok.removeAll { $0.name == name } }
        return nil
    }

    /// Adds `NAME regex` lines, as Logstash and StreamSets pattern files write them,
    /// as the user's own definitions (replacing ones of the same name). Blank lines
    /// and `#` comments are skipped; a line that isn't `NAME regex`, or whose regex
    /// doesn't compile, is reported and not added.
    func pasteGrokDefinitions(_ text: String) -> [String] {
        var problems: [String] = []
        var pasted: [(line: Int, definition: GrokDefinition)] = []
        // Any line ending: "\r\n" is one Character, which splitting on "\n" misses.
        for (offset, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, GrokDefinition.isValidName(String(parts[0])) else {
                problems.append("Line \(offset + 1): \"\(trimmed)\" isn't NAME regex")
                continue
            }
            let regex = parts[1].trimmingCharacters(in: .whitespaces)
            pasted.append((offset + 1, GrokDefinition(name: String(parts[0]), regex: regex)))
        }
        // `grok` is what gets written; `checked` is what the next load checks it
        // against: every definition the file has, broken ones too.
        var grok = config.grok
        var checked = grokForPatterns
        for (_, definition) in pasted {
            grok = Self.replacing(definition, in: grok)
            checked = Self.replacing(definition, in: checked)
        }
        // A broken paste leaves the definition it would replace as it was.
        func takeBack(_ definition: GrokDefinition) {
            grok = Self.restoring(definition.name, from: config.grok, in: grok)
            checked = Self.restoring(definition.name, from: grokForPatterns, in: checked)
        }
        let all = checked
        for (line, definition) in pasted {
            if case .failure(let error) = compileGrokDefinition(definition, grok: all) {
                problems.append("Line \(line): \(definition.name): \(error.message)")
                takeBack(definition)
            }
        }
        // Nor is one added that would break a Pattern or definition using its name,
        // which the next load would skip.
        var kept: [(line: Int, definition: GrokDefinition)] { pasted.filter { grok.contains($0.definition) } }
        for (line, definition) in kept {
            let changed = Set(kept.map(\.definition.name))
            guard let broken = firstBroken(by: checked, besides: changed) else { break }
            let without = Self.restoring(definition.name, from: grokForPatterns, in: checked)
            guard firstBroken(by: without, besides: changed) != broken else { continue }
            problems.append("Line \(line): \(definition.name): \(broken)")
            takeBack(definition)
        }
        let sorted = problems.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        // What's left is checked once more as a whole, since one taken back can be
        // what another, or a Pattern, needed. Broken only together: none is added.
        let stillBroken = firstBroken(by: checked, besides: Set(kept.map(\.definition.name))) ?? kept.lazy.compactMap { line, definition in
            if case .failure(let error) = compileGrokDefinition(definition, grok: checked) {
                "Line \(line): \(definition.name): \(error.message)"
            } else {
                nil
            }
        }.first
        if let stillBroken { return sorted + ["\(stillBroken); nothing was added"] }
        if grok != config.grok { apply { $0.grok = grok } }
        return sorted
    }

    /// `definition` in place of the one of its name in `grok`, or at the end.
    private static func replacing(_ definition: GrokDefinition, in grok: [GrokDefinition]) -> [GrokDefinition] {
        var grok = grok
        if let index = grok.firstIndex(where: { $0.name == definition.name }) {
            grok[index] = definition
        } else {
            grok.append(definition)
        }
        return grok
    }

    /// `grok` with the definition called `name` as `original` has it, or without one.
    private static func restoring(_ name: String, from original: [GrokDefinition], in grok: [GrokDefinition]) -> [GrokDefinition] {
        if let definition = original.first(where: { $0.name == name }) { return replacing(definition, in: grok) }
        return grok.filter { $0.name != name }
    }

    /// The first Pattern, or user definition not named in `changed`, that wouldn't
    /// compile against `grok`, as a problem to show; nil when all would. All of them
    /// compile against the file's own definitions, as loading checked, so a failure
    /// here is the change's doing.
    private func firstBroken(by grok: [GrokDefinition], besides changed: Set<String>) -> String? {
        for pattern in config.patterns {
            if let regex = pattern.regex, case .failure(let error) = compileRegex(regex, grok: grok) {
                return "Pattern \"\(pattern.name)\" uses it and wouldn't compile: \(error.message)"
            }
        }
        for definition in config.grok where !changed.contains(definition.name) {
            if case .failure(let error) = compileGrokDefinition(definition, grok: grok) {
                return "\(definition.name) uses it and wouldn't compile: \(error.message)"
            }
        }
        return nil
    }

    /// Adds a User Pattern that highlights what a definition matches: named after
    /// it, lowercased with `_` as spaces, with the regex `%{NAME}` and Copy. It
    /// opens in the Pattern editor, unless it couldn't be added.
    func newPattern(fromGrok name: String) {
        commitEditedRegex()
        var patternName = name.lowercased().replacingOccurrences(of: "_", with: " ")
        if BuiltinID(rawValue: patternName) != nil { patternName += " pattern" }
        let regex = "%{\(name)}"
        // Checked as loading would, so a broken definition of that name isn't written.
        if case .failure(let error) = compileRegex(regex, grok: grokForPatterns) {
            refuse(because: "Couldn't add a Pattern for \(name): \(error.message)")
            return
        }
        let pattern = Pattern(name: patternName, regex: regex, actions: [.copy])
        guard apply({ $0.patterns.append(pattern) }), config.patterns.last == pattern else { return }
        selectedPattern = config.patterns.count - 1
        section = .patterns
    }
}
