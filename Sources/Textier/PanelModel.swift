import AppKit
import Observation
import Synchronization
import TextierCore

/// The Panel's state, shared by its AppKit Input and its SwiftUI Inspector.
@MainActor
@Observable
final class PanelModel {
    /// The current Inspection; its `selection` is the Inspector's selected entry.
    private(set) var inspection = Inspection(matches: [], tabs: [], selection: nil)
    /// Bumped whenever the Inspection's tabs change (a new inspection, a tab
    /// moved), not for a new selection: the row list rebuilds on it rather than
    /// comparing every entry.
    private(set) var tabsRevision = 0
    /// A Panel setting: whether the Input shows tints and click behaviour.
    var highlighting = true {
        didSet { onHighlightingChange(highlighting) }
    }
    /// Whether the Input wraps long lines, or scrolls sideways; remembered between launches.
    var wrapsLines = UserDefaults.standard.object(forKey: PanelModel.wrapsLinesKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(wrapsLines, forKey: Self.wrapsLinesKey)
            onWrapChange(wrapsLines)
        }
    }
    static let wrapsLinesKey = "inputWrapsLines"
    /// The Pattern names in the order the user dragged their tabs into; remembered
    /// between launches.
    @ObservationIgnored private var tabOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.tabOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.tabOrderKey) }
    }
    static let tabOrderKey = "inspectorTabOrder"
    /// Posted when a tab is moved, so every Inspector (the Panel's, the Selection
    /// Popover's) follows the new order at once.
    static let tabOrderDidChange = Notification.Name("textier.tabOrderDidChange")
    @ObservationIgnored private var tabOrderChanges: NotificationObservation?
    /// The header badge's warnings: config, theme, shortcut and editor warnings,
    /// and the Accessibility note, then one for each Pattern the last inspection
    /// stopped for taking too long.
    var warnings: [String] {
        otherWarnings + inspection.slowPatterns.map { name in
            "Pattern \"\(name)\" was stopped after \(Self.secondsText(inspection.timeLimit)) s; "
                + "some of its Matches may be missing"
        }
    }
    private var otherWarnings: [String] = []
    /// The longest Input the Panel takes, in UTF-16 units (100 MB of ASCII text).
    /// Text that would make it longer is refused (`refuse(length:)`).
    nonisolated static let largestInput = 100 * 1_048_576
    /// Why the last text was refused, until the Input changes again.
    private(set) var refusal: String?

    /// Says that text which would make the Input `length` long was refused.
    func refuse(length: Int) {
        refusal = "Too large for the Panel: \(Self.megabytes(length)) MB, the limit is \(Self.megabytes(Self.largestInput)) MB"
    }

    func clearRefusal() {
        if refusal != nil { refusal = nil }
    }

    /// A length in UTF-16 units as whole MB, rounded up.
    static func megabytes(_ length: Int) -> Int {
        (length + 1_048_575) / 1_048_576
    }

    /// Whether a large Input is being inspected in the background (`inspect`).
    private(set) var isInspecting = false
    /// How far that inspection has got, in whole percent, while `isInspecting`.
    private(set) var inspectionPercent = 0

    /// `2`, or `2.5`: a time limit in seconds, as the warning says it.
    static func secondsText(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
    }
    /// How the Inspector groups Matches: the Config's `inspectorLayout` to start
    /// with, then the toolbar switch (⌘L) until the app quits or the Config's value
    /// changes.
    var layout = InspectorLayout.tabs
    /// The Config's `inspectorLayout` as last seen, so a reload only resets the
    /// switch when that key changed.
    @ObservationIgnored private var configuredLayout: InspectorLayout?
    /// The groups collapsed in the list layout; kept while the Panel stays open.
    private(set) var collapsed: Set<InspectorTab.ID> = []
    /// Whether the Inspector's row list has keyboard focus, so the selected row
    /// shows a focus ring in place of the system highlight.
    var listHasFocus = false
    /// Whether a datetime entry shows its conversions re-read as UTC.
    var readsDatetimeAsUTC = false

    /// Called after each inspection pass with the new Inspection.
    @ObservationIgnored var onInspectionChange: (Inspection) -> Void = { _ in }
    /// Called when the user selects an entry, so the Input selects its range.
    @ObservationIgnored var onSelectEntry: (InspectorEntry) -> Void = { _ in }
    @ObservationIgnored var onHighlightingChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var onWrapChange: (Bool) -> Void = { _ in }
    /// Called when Shift-Tab or Tab in the Inspector asks for the Input.
    @ObservationIgnored var onFocusInput: () -> Void = {}
    /// Called when Tab or Shift-Tab in the Input asks for the Inspector's list.
    @ObservationIgnored var onFocusList: () -> Void = {}

    // MARK: Inspecting

    /// Inputs this long (UTF-16 units) or longer are inspected in the background. A
    /// match-dense log this long takes about 130 ms to inspect, before the pills and
    /// the Inspector are drawn; any longer and typing visibly stalls. Shorter ones
    /// stay synchronous, so the Inspector catches up at once.
    nonisolated static let backgroundThreshold = 200_000
    /// Background inspections, one at a time, in order. Internal rather than private
    /// so the app tests can wait for one.
    static let inspections = DispatchQueue(label: "textier.Inspection", qos: .userInitiated)
    /// Numbers each inspection started, and each edit, so a background result a
    /// newer inspection or an edit overtook is dropped (one still queued isn't run at
    /// all, and one running stops).
    @ObservationIgnored private let generation = Generation()

    /// Inspects `input` afresh (a capture or a wholesale paste), or keeping the
    /// previous tab order and selection (an edit, a config reload).
    ///
    /// An Input of `backgroundThreshold` or longer is inspected on a queue of its
    /// own, and the result comes back through the main run loop (so it also comes
    /// while the app tests hold the main queue). Meanwhile `isInspecting` is set
    /// and the last Inspection stays, its pills following edits; a fresh one has
    /// none, since they'd describe text that's gone. A selection made meanwhile is
    /// kept, as an edit's inspection keeps it.
    func inspect(_ input: String, fresh: Bool) {
        let config = AppConfig.current
        let previous = fresh ? nil : inspection
        let now = Date()
        let started = generation.next()
        guard (input as NSString).length >= Self.backgroundThreshold else {
            isInspecting = false
            apply(
                TextierCore.inspect(
                    input, config: config, previous: previous, now: now, timeZone: .current,
                    fileExists: { FileManager.default.fileExists(atPath: $0) }
                ),
                fresh: fresh, config: config
            )
            return
        }
        isInspecting = true
        inspectionPercent = 0
        if fresh { apply(Inspection(matches: [], tabs: [], selection: nil), fresh: true, config: config) }
        let timeZone = TimeZone.current
        let generation = generation
        // @Sendable, so the block isn't main-actor code: it runs on `inspections`, and
        // Swift traps a main-actor closure that runs anywhere but the main queue.
        Self.inspections.async { @Sendable [weak self] in
            guard generation.isLatest(started) else { return }
            // Detection is most of an inspection: its share done shows as 0–90%, and
            // only when the whole percent changes.
            let lastPercent = Mutex(0)
            let next = TextierCore.inspect(
                input, config: config, previous: previous, now: now, timeZone: timeZone,
                isCancelled: { !generation.isLatest(started) },
                progress: { fraction in
                    let percent = Int(fraction * 90)
                    guard lastPercent.withLock({ last in
                        defer { last = max(last, percent) }
                        return percent > last
                    }) else { return }
                    RunLoop.main.perform(inModes: [.common]) {
                        MainActor.assumeIsolated {
                            guard let self, generation.isLatest(started) else { return }
                            self.inspectionPercent = max(self.inspectionPercent, percent)
                        }
                    }
                },
                fileExists: { FileManager.default.fileExists(atPath: $0) }
            )
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    guard let self, generation.isLatest(started) else { return }
                    var next = next
                    // The user picked another entry while this ran: keep that one.
                    if self.inspection.selection != previous?.selection {
                        next.selection = next.selection(keeping: self.inspection)
                    }
                    self.isInspecting = false
                    self.apply(next, fresh: fresh, config: config)
                }
            }
        }
    }

    /// The Input changed: a background inspection still running describes the text
    /// before the edit, so its result is dropped. The edit's own inspection comes
    /// after the typing pause, and `isInspecting` stays set until it lands.
    func inputDidChange() {
        _ = generation.next()
    }

    /// Makes `next`, an inspection of the Input with `config`, the current one: in
    /// the user's tab order, with a selection, and the layout following the Config's.
    private func apply(_ next: Inspection, fresh: Bool, config: Config) {
        var next = next
        if fresh { lastIndex = [:] }
        if fresh || next.selection?.tab != inspection.selection?.tab { readsDatetimeAsUTC = false }
        next.tabs = arrangedTabs(next.tabs, order: tabOrder)
        if next.selection == nil { next.selection = next.tabs.first.map { EntryID(tab: $0.id, index: 0) } }
        if config.inspectorLayout != configuredLayout {
            configuredLayout = config.inspectorLayout
            layout = config.inspectorLayout
        }
        inspection = next
        tabsRevision += 1
        onInspectionChange(next)
    }

    /// Drags the Pattern tab named `name` to `index` among the Pattern tabs, and
    /// remembers the arrangement for later captures.
    func moveTab(named name: String, to index: Int) {
        tabOrder = arrangingTab(name, to: index, shown: patternTabs.map(\.title), order: tabOrder)
        NotificationCenter.default.post(name: Self.tabOrderDidChange, object: self)
    }

    init() {
        tabOrderChanges = NotificationObservation(Self.tabOrderDidChange, object: nil) { [weak self] in
            guard let self else { return }
            inspection.tabs = arrangedTabs(inspection.tabs, order: tabOrder)
            tabsRevision += 1
        }
    }

    /// Every tab but Plain Text.
    var patternTabs: [InspectorTab] {
        inspection.tabs.filter { $0.id != .plainText }
    }

    /// How many Matches the Pattern tabs hold, nested ones included.
    var matchCount: Int {
        patternTabs.reduce(0) { $0 + $1.entries.count }
    }

    /// The header's "4 Patterns · 9 Matches".
    var countLine: String {
        counted(patternTabs.count, "Pattern") + " · " + counted(matchCount, "Match")
    }

    /// A tab's Pattern color, or Plain Text's neutral grey.
    func color(of tab: InspectorTab) -> PatternColor {
        tab.color ?? Palette.plainText
    }

    /// The selected entry when it's a Match, with its color (a Color Rule's, or its
    /// tab's), for ringing it in the text.
    var selectedMatch: (entry: InspectorEntry, color: PatternColor)? {
        guard let id = inspection.selection, id.tab != .plainText, let entry = inspection.entry(id) else { return nil }
        return (entry, entry.color ?? inspection.tab(id.tab).map(color(of:)) ?? Palette.fallback)
    }

    /// The color of the tab a nested Match's parent is in.
    func color(ofParent parent: ParentTag) -> PatternColor {
        inspection.tab(.pattern(parent.patternName))?.color ?? Palette.fallback
    }

    // MARK: Selection

    var selectedTab: InspectorTab? {
        inspection.selection.flatMap { inspection.tab($0.tab) } ?? inspection.tabs.first
    }

    var selectedEntry: InspectorEntry? { inspection.selectedEntry }

    /// Selects an entry and shows its range in the Input.
    func select(_ id: EntryID) {
        guard let entry = inspection.entry(id) else { return }
        if inspection.selection?.tab != id.tab { readsDatetimeAsUTC = false }
        inspection.selection = id
        lastIndex[id.tab] = id.index
        collapsed.remove(id.tab)
        onSelectEntry(entry)
    }

    func isCollapsed(_ id: InspectorTab.ID) -> Bool {
        collapsed.contains(id)
    }

    /// Collapses or expands a group in the list layout.
    func setCollapsed(_ id: InspectorTab.ID, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(id) } else { collapsed.remove(id) }
    }

    /// The tab's first entry, or the one last selected in it while it still exists.
    func selectTab(_ id: InspectorTab.ID) {
        guard id != inspection.selection?.tab, let tab = inspection.tab(id) else { return }
        let index = lastIndex[id].flatMap { tab.entries.indices.contains($0) ? $0 : nil } ?? 0
        select(EntryID(tab: id, index: index))
    }

    /// ⌘1–⌘9: the `number`th tab (or section), from 1. Returns false when there's no such tab.
    func selectTab(number: Int) -> Bool {
        guard inspection.tabs.indices.contains(number - 1) else { return false }
        selectTab(inspection.tabs[number - 1].id)
        return true
    }

    /// Selects the Inspector entry for a top-level Match, as a double-click in the Input does.
    func select(_ match: Match) {
        guard let id = inspection.entryID(for: match) else { return }
        select(id)
    }

    /// The entry index last selected in each tab, for switching back.
    @ObservationIgnored private var lastIndex: [InspectorTab.ID: Int] = [:]

    // MARK: Actions

    var isPlainTextSelected: Bool { inspection.selection?.tab == .plainText }

    /// The title a Match Window from the selected entry gets.
    var selectedPatternName: String {
        selectedTab?.title ?? ""
    }

    /// Return or a double-click on a list row.
    func runFirstAction() {
        guard let entry = selectedEntry,
              let item = entry.barItems(isPlainText: isPlainTextSelected, inMatchWindow: false).first
        else { return }
        run(item, on: entry)
    }

    func run(_ item: ActionBarItem, on entry: InspectorEntry) {
        switch item {
        case .action(let action): action.perform(on: entry, patternName: selectedPatternName)
        case .popOut: MatchWindowController.open(entry, patternName: selectedPatternName)
        case .copyWithLine: entry.pathWithLine.map(copyToPasteboard)
        }
    }

    /// ⌘⇧P.
    func popOut() {
        guard let entry = selectedEntry, !isPlainTextSelected else { return }
        MatchWindowController.open(entry, patternName: selectedPatternName)
    }

    // MARK: Focus and warnings

    func focusList() {
        onFocusList()
    }

    func focusInput() {
        onFocusInput()
    }

    func setWarnings(_ warnings: [String]) {
        otherWarnings = warnings
    }
}

/// The number of the latest inspection a Panel started, shared with its
/// background queue.
private final class Generation: Sendable {
    private let latest = Mutex(0)

    /// Starts an inspection: its number.
    func next() -> Int {
        latest.withLock { latest in
            latest += 1
            return latest
        }
    }

    func isLatest(_ generation: Int) -> Bool {
        latest.withLock { $0 == generation }
    }
}

/// "1 Match", "9 Matches": `count` and `noun`, plural when it isn't 1.
func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : noun.hasSuffix("ch") ? "es" : "s")"
}
