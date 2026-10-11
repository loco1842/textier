import Foundation
import Observation
import TextierCore

/// Settings' state: the values the config file holds, the drafts of values the
/// user entered that aren't valid, and the config warnings by section.
///
/// The config file stays the source of truth. Every valid edit is written to it at
/// once through the config store, which loads it straight back, so the Panel
/// follows; an invalid one stays a draft, shown inline, and isn't written. When
/// the file is saved from outside, the values follow it and any draft stays on
/// top, noting that the file changed underneath.
@MainActor
@Observable
final class SettingsModel {
    /// The parts of Settings, in sidebar order.
    enum Section: String, CaseIterable, Identifiable {
        case general, appearance, patterns, grokDefinitions

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .patterns: "Patterns"
            case .grokDefinitions: "Grok Definitions"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .patterns: "text.magnifyingglass"
            case .grokDefinitions: "books.vertical"
            }
        }
    }

    /// A value Settings can hold a draft of.
    enum Setting: Hashable {
        case shortcut
        /// The name or regex of the Pattern at an index in the Config.
        case patternName(Int)
        case patternRegex(Int)
        /// The regex of the user's Grok Definition with this name.
        case grokRegex(String)
    }

    /// An entered value that isn't valid, so it isn't in the file.
    struct Draft: Equatable {
        /// What the user entered, as its field shows it.
        var text: String
        /// Why it can't be saved, shown under the field.
        var problem: String
        /// Set when the file was saved from outside since the draft began, so the
        /// value in the file may not be the one the user started from.
        var fileChanged = false
    }

    let store: ConfigStore
    /// The selected section.
    var section = Section.general
    var drafts: [Setting: Draft] = [:]
    /// What the Patterns list is narrowed to: text in a Pattern's name or regex.
    var patternFilter = ""
    /// The index of the Pattern open in the editor.
    var selectedPattern: Int? {
        didSet {
            if selectedPattern != oldValue { editedRegex = nil }
        }
    }
    /// The regex as typed in the editor, before it's committed (Return, or leaving
    /// the field); nil while the field shows the file's regex or its draft.
    var editedRegex: String?
    /// What the Grok Definitions lists are narrowed to: text in a definition's name.
    var grokFilter = ""
    /// The text in the Pattern editor's test box: the Panel's Input when Settings
    /// opened (its start, when it's long), then whatever the user types.
    var testInput = ""
    /// Where the user last clicked in the test box, for the Match whose Fields show.
    var testSelection: Int?
    /// Why the last edit couldn't be written, until one can be.
    private(set) var writeError: String?

    /// The test box's last run and its Matches, for `testMatches`.
    @ObservationIgnored var lastTestRun: (run: TestRun, matches: Result<[Match], RegexError>)?
    @ObservationIgnored private var isWriting = false
    /// The Config as of the last load, to follow Patterns an outside edit moved.
    @ObservationIgnored private var lastConfig: Config
    @ObservationIgnored private var reloads: NotificationObservation?

    init(store: ConfigStore) {
        self.store = store
        lastConfig = store.config
        reloads = NotificationObservation(ConfigStore.didReload, object: store) { [weak self] in
            self?.storeDidReload()
        }
    }

    /// The values the file holds (the last good ones while it can't be used).
    var config: Config { store.config }

    func draft(_ setting: Setting) -> Draft? {
        drafts[setting]
    }

    /// Drops a draft, so its field shows the file's value again.
    func discardDraft(_ setting: Setting) {
        drafts[setting] = nil
    }

    // MARK: General

    /// A key press from the shortcut recorder: written when it makes a Shortcut,
    /// otherwise kept as a draft saying why not.
    func recordShortcut(modifiers: Shortcut.Modifiers, key: String) {
        if let shortcut = Shortcut(modifiers: modifiers, key: key) {
            setShortcut(shortcut)
            return
        }
        let problem = Shortcut.keys.contains(key)
            ? "Add ⌃, ⌥ or ⌘, so the shortcut doesn't take over typing"
            : "A shortcut's key is a letter, a digit, F1–F12 or Space"
        keepDraft(.shortcut, text: Shortcut.symbols(modifiers: modifiers, key: key), problem: problem)
    }

    func setShortcut(_ shortcut: Shortcut) {
        apply(clearing: .shortcut) { $0.shortcut = shortcut }
    }

    /// Any text is a valid command; an empty one means unset.
    func setEditorCommand(_ command: String) {
        apply { $0.editorCommand = command.isEmpty ? nil : command }
    }

    /// Opens the config file with the editor command, as Open in Editor would; a
    /// command that won't run shows the editor warning in General.
    func testEditorCommand() {
        openConfigFile()
    }

    func setCopyJSON(_ copyJSON: CopyJSON) {
        apply { $0.copyJSON = copyJSON }
    }

    func setInspectorLayout(_ layout: InspectorLayout) {
        apply { $0.inspectorLayout = layout }
    }

    // MARK: Appearance

    /// System, Light or Dark; the app follows once the file is written.
    func setAppearance(_ appearance: AppearanceSetting) {
        apply { $0.appearance = appearance }
    }

    // MARK: Warnings

    /// What the selected section's warning block lists: why the last edit wasn't
    /// written, then the section's warnings.
    var sectionMessages: [String] {
        [writeError].compactMap { $0 } + warnings(in: section).map(\.message)
    }

    /// The config, shortcut and editor warnings about `section`.
    func warnings(in section: Section) -> [ConfigWarning] {
        var bySection: [(Section, ConfigWarning)] = store.loadWarnings.map { (Self.section(forLoadWarning: $0.message), $0) }
        bySection += [store.shortcutWarning, store.editorWarning].compactMap { $0 }.map { (.general, $0) }
        return bySection.filter { $0.0 == section }.map(\.1)
    }

    /// The section a warning from loading the config file is about, by what it names.
    static func section(forLoadWarning message: String) -> Section {
        if message.hasPrefix("Pattern ") { return .patterns }
        if message.hasPrefix("Grok Definition ") || message.hasPrefix(#""grok""#) { return .grokDefinitions }
        if message.hasPrefix(#""appearance""#) || message.hasPrefix(#""theme""#) { return .appearance }
        return .general
    }

    /// Opens the config file in the editor, to fix a warning at its cause.
    func openConfigFile() {
        Effects.openFile(store.fileURL.path, nil)
    }

    // MARK: Writing

    /// Writes a valid edit: the Config with `change` made, which the store loads
    /// straight back. `setting`'s draft, if any, is settled by it once it's written.
    /// Refused while the file can't be used, so a file being fixed by hand isn't
    /// overwritten with the last good Config. When it isn't written, `text` (what
    /// the user entered for `setting`) stays as a draft saying why, so it isn't
    /// lost. Returns whether it wrote.
    @discardableResult
    func apply(clearing setting: Setting? = nil, text: String? = nil, _ change: (inout Config) -> Void) -> Bool {
        if let fatal = store.loadWarnings.first(where: \.isFatal) {
            return refuse(setting, text: text, because: "Settings won't overwrite the config file until it can be read: \(fatal.message)")
        }
        var config = store.config
        change(&config)
        isWriting = true
        defer { isWriting = false }
        do {
            try store.write(config)
            if let setting { drafts[setting] = nil }
            writeError = nil
            return true
        } catch {
            return refuse(setting, text: text, because: "Couldn't write \(store.fileURL.path): \(error.localizedDescription)")
        }
    }

    /// An edit that isn't written: says why, and keeps the text entered for
    /// `setting` as its draft.
    @discardableResult
    func refuse(_ setting: Setting? = nil, text: String? = nil, because problem: String) -> Bool {
        writeError = problem
        if let setting, let text { keepDraft(setting, text: text, problem: problem) }
        return false
    }

    /// Keeps an invalid edit as a draft, unwritten.
    func keepDraft(_ setting: Setting, text: String, problem: String) {
        drafts[setting] = Draft(text: text, problem: problem)
    }

    /// After every load: one from outside marks the drafts, since the file changed
    /// underneath them, and moves a Pattern's drafts to wherever its Pattern went.
    /// Settings' own writes don't.
    private func storeDidReload() {
        if !store.loadWarnings.contains(where: \.isFatal) { writeError = nil }
        defer { lastConfig = config }
        guard !isWriting else { return }
        for setting in drafts.keys { drafts[setting]?.fileChanged = true }
        renumberPatterns { [lastConfig, config] in Self.index(of: $0, in: lastConfig, within: config) }
    }

    /// Where the Pattern at `index` in `old` is in `new`: the same name, and the same
    /// place among the Patterns of that name.
    private static func index(of index: Int, in old: Config, within new: Config) -> Int? {
        guard old.patterns.indices.contains(index) else { return nil }
        let name = old.patterns[index].name
        let ordinal = old.patterns[..<index].filter { $0.name == name }.count
        let matching = new.patterns.indices.filter { new.patterns[$0].name == name }
        return matching.indices.contains(ordinal) ? matching[ordinal] : nil
    }
}

extension Shortcut {
    /// How macOS menus write it: ⌃⌥T.
    var symbols: String {
        Self.symbols(modifiers: modifiers, key: key)
    }

    /// The symbols for a key press, whether or not it makes a Shortcut.
    static func symbols(modifiers: Modifiers, key: String) -> String {
        let names: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keyName = key == "space" ? "Space" : key.uppercased()
        return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }
}

/// A block observer of one notification, removed when this is released.
final class NotificationObservation {
    private let token: NSObjectProtocol

    /// `handler` runs on the thread that posts, which for the config store is the
    /// main one. A nil `object` takes the notification from any sender.
    @MainActor
    init(_ name: Notification.Name, object: AnyObject?, handler: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
