import AppKit
import SwiftUI
import TextierCore

/// The Selection Popover's state: the text the shortcut captured (the selection in
/// the app in front), inspected as the Panel inspects its Input, with a preview of
/// its first lines carrying the pills, and its Matches as one list, filtered by
/// Pattern or not, where one row at a time is open on its parsed view. The text
/// can be edited, typed or pasted into in the preview, and is inspected again
/// after a pause, as the Panel's Input is. It never reads the clipboard: the menu
/// bar icon shows the last text again, until it's cleared (by hand, or a while
/// after the popover closes when the config's `clearSelectionAfter` says so).
@MainActor
@Observable
final class SelectionPopoverModel {
    /// The popover's own Inspector state, apart from the Panel's.
    let inspector = PanelModel()
    private(set) var text = ""
    /// The shortcut has captured something, a selection or that there was none.
    private(set) var hasCaptured = false
    /// The last capture found no selection because textier lacks Accessibility.
    private(set) var lacksAccessibility = false
    /// Closes the popover (Esc in the preview).
    @ObservationIgnored var onClose: () -> Void = {}
    /// The selection is too long to inspect here; the Panel takes it.
    private(set) var isTooLarge = false
    /// The selection is too long for the Panel too (`PanelModel.largestInput`).
    private(set) var isTooLargeForPanel = false
    /// The most characters (UTF-16) the popover inspects.
    static let largestInspected = 1_000_000
    /// When the shortcut captured the text.
    private(set) var selectedAt: Date?
    /// The text, read-only, with its Matches as pills.
    @ObservationIgnored let preview: InputTextView
    /// Opens the text in the Panel (the popover closes first).
    @ObservationIgnored var onOpenInPanel: (String) -> Void
    /// The clock; the app tests set it to show time passing.
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The text when it was too long, for Open in Panel (never shown).
    @ObservationIgnored private var heldText = ""
    /// The inspection after a pause in editing the preview.
    @ObservationIgnored private var reinspection: Timer?
    /// Clears the text a while after the popover closed (`didClose`).
    @ObservationIgnored private var clearing: Timer?
    @ObservationIgnored private var edits: NotificationObservation?

    /// A Match in the list: its entry and the tab it's in.
    struct Row: Identifiable {
        let id: EntryID
        let entry: InspectorEntry
        let tab: InspectorTab
    }

    /// The Pattern whose Matches the list shows, or nil for all of them.
    var filter: InspectorTab.ID? {
        didSet { updateRows() }
    }
    /// The list: every Match in the order it comes in the text (a Match before
    /// those inside it), or the filter's Pattern's alone, up to `largestList`.
    private(set) var rows: [Row] = []
    /// The Matches past `largestList`, left to the Panel.
    private(set) var hiddenRowCount = 0
    /// The most rows the list holds, so the arrows and redraws stay quick.
    static let largestList = 1_000
    /// Bumped when the list should take the keyboard: the popover opening on text.
    private(set) var focusRequests = 0
    /// Bumped for each new selection, which shows from the list's top.
    private(set) var newSelections = 0
    /// The row open on its parsed view under it, one at a time: the row clicked,
    /// or the one the arrows or a pill select while a card is open (a row's buttons
    /// select without moving it). An edit keeps it on its Match; nil when all are
    /// closed, as after a new selection or when the open row leaves the list.
    private(set) var openRow: EntryID?
    /// The Matches of every Pattern, in text order, for `rows`.
    @ObservationIgnored private var allRows: [Row] = []

    /// The most lines the preview shows before it scrolls.
    static let previewLines = 3

    init(openInPanel: @escaping (String) -> Void = { _ in }) {
        onOpenInPanel = openInPanel
        preview = InputTextView.make()
        // One row per line, as logs read best; the rest scrolls.
        preview.wrapsLines = false
        preview.textContainerInset = NSSize(width: 8, height: 6 + PillLayoutManager.lineSpacing / 2)
        inspector.onInspectionChange = { [weak self] inspection in
            guard let self else { return }
            preview.matches = inspection.matches
            // The open row is found again by its Match, not its index, which an
            // edit before it shifts.
            let opened = openRow.flatMap { id in allRows.first { $0.id == id } }
            allRows = Self.rows(of: inspection)
            let reopened = opened.flatMap { Self.row(matching: $0, in: allRows) }
            if openRow != reopened { openRow = reopened }
            updateRows()
            showSelection()
        }
        inspector.onSelectEntry = { [weak self] entry in
            guard let self else { return }
            showSelection()
            preview.scrollRangeToVisible(entry.range)
        }
        inspector.onHighlightingChange = { [weak self] in self?.preview.highlighting = $0 }
        // A ⌘-click on a pill selects it in the list (shown, if a filter hid it), the
        // keyboard staying in the text for editing.
        preview.onClick = { [weak self] match in
            guard let self else { return }
            inspector.select(match)
            if let tab = inspector.inspection.selection?.tab, filter != nil, filter != tab { filter = nil }
            // An open card follows; with none open, the pill only selects.
            if openRow != nil { openSelection() }
        }
        // Esc closes the popover, even with the preview's text selected.
        preview.onCancel = { [weak self] in self?.onClose() }
        edits = NotificationObservation(NSText.didChangeNotification, object: preview) { [weak self] in
            self?.textDidChange()
        }
    }

    /// Typing or pasting in the preview: the text follows at once (Open in Panel
    /// takes it), and is inspected again after a pause, as the Panel's Input is.
    private func textDidChange() {
        text = preview.string
        isTooLarge = false
        isTooLargeForPanel = false
        heldText = ""
        inspector.inputDidChange()
        reinspection?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.inspectEdit() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reinspection = timer
    }

    private func inspectEdit() {
        lineCount = text.isEmpty ? 0 : text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
        // What typing brings in fades in, as in the Panel.
        preview.fadesNewPills = true
        inspector.inspect(text, fresh: false)
    }

    /// "8 lines · selected 2 min ago"; the lines alone for text typed or pasted in.
    var subtitle: String {
        guard let selectedAt else { return text.isEmpty ? "" : counted(lineCount, "line") }
        let now = self.now()
        let ago = now.timeIntervalSince(selectedAt) < 10
            ? "just now" : RelativeDateTimeFormatter().localizedString(for: selectedAt, relativeTo: now)
        return counted(lineCount, "line") + " · selected " + ago
    }

    /// The text's lines, counted once per selection: LF, CRLF and lone CR alike.
    private var lineCount = 0

    /// Shows what the shortcut captured: the selection, or nil when there was none
    /// (nothing selected, or no Accessibility to copy it).
    func show(selection: String?, lacksAccessibility: Bool = false) {
        clearing?.invalidate()
        let string = selection ?? ""
        hasCaptured = true
        self.lacksAccessibility = lacksAccessibility
        selectedAt = now()
        let length = (string as NSString).length
        isTooLarge = length > Self.largestInspected
        isTooLargeForPanel = length > PanelModel.largestInput
        heldText = isTooLarge ? string : ""
        text = isTooLarge ? "" : string
        lineCount = text.isEmpty ? 0 : text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
        reinspection?.invalidate()
        preview.string = text
        // A new selection isn't the edit before it: no undoing into it.
        preview.undoManager?.removeAllActions()
        preview.fadesNewPills = false
        filter = nil
        openRow = nil
        newSelections += 1
        inspector.inspect(text, fresh: true)
        // A new selection shows from its start.
        preview.scroll(.zero)
    }

    /// The popover opening: the list takes the keyboard, or with no text yet, the
    /// preview, ready for a paste.
    func didOpen() {
        clearing?.invalidate()
        if text.isEmpty, !isTooLarge {
            preview.window?.makeFirstResponder(preview)
        } else {
            focusRequests += 1
        }
    }

    /// The popover closing: with `seconds` above 0 (the config's
    /// `clearSelectionAfter`), the text clears that long after, unless the popover
    /// opens again first.
    func didClose(clearingAfter seconds: TimeInterval) {
        clearing?.invalidate()
        guard seconds > 0, canClear else { return }
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clearing = timer
    }

    /// There's something to clear: text, or what the last capture found.
    var canClear: Bool {
        !text.isEmpty || isTooLarge || hasCaptured
    }

    /// Back to before the first selection: no text, nothing to undo, and the menu
    /// bar icon opens an empty popover, ready to paste into.
    func clear() {
        clearing?.invalidate()
        reinspection?.invalidate()
        hasCaptured = false
        lacksAccessibility = false
        selectedAt = nil
        isTooLarge = false
        isTooLargeForPanel = false
        heldText = ""
        text = ""
        lineCount = 0
        preview.string = ""
        preview.undoManager?.removeAllActions()
        filter = nil
        openRow = nil
        inspector.inspect("", fresh: true)
        // Open, the keyboard goes to the emptied text, for a paste.
        if preview.window?.isVisible == true { preview.window?.makeFirstResponder(preview) }
    }

    /// After a config reload: the text inspected again with the new Patterns.
    func configDidChange() {
        guard !text.isEmpty else { return }
        inspector.inspect(text, fresh: false)
    }

    /// The text in the Panel; the whole of it, when it was too long to inspect here.
    func openInPanel() {
        onOpenInPanel(isTooLarge ? heldText : text)
    }

    /// The preview's height: its lines up to `previewLines`, then it scrolls.
    var previewHeight: CGFloat {
        let font = preview.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let line = (preview.layoutManager?.defaultLineHeight(for: font) ?? 16) + PillLayoutManager.lineSpacing
        // The top inset, the lines, and half a line's spacing below the last, which
        // keeps the next line's pills out of sight.
        // Empty, it's all its lines tall, room to paste into.
        let lines = text.isEmpty ? Self.previewLines : min(max(lineCount, 1), Self.previewLines)
        return preview.textContainerInset.height + CGFloat(lines) * line
            - PillLayoutManager.lineSpacing / 2 + 1
    }

    /// The lines past what the preview shows.
    var hiddenLineCount: Int {
        max(0, lineCount - Self.previewLines)
    }

    /// Selects `row`, ringing its pill in the preview.
    func select(_ row: Row) {
        inspector.select(row.id)
    }

    /// One of a row's buttons.
    func run(_ item: ActionBarItem, on row: Row) {
        select(row)
        inspector.run(item, on: row.entry)
    }

    /// A chip: only `tab`'s Matches, or all of them. A selection the filter hides
    /// moves to the first row shown, so Return never acts on a row out of sight.
    func show(only tab: InspectorTab.ID?) {
        filter = tab
        if let first = rows.first, !rows.contains(where: { $0.id == inspector.inspection.selection }) {
            select(first)
        }
    }

    /// Up and Down: the row before or after the selected one, in the list. An open
    /// card follows, the row moved to opening in its place.
    func moveSelection(by offset: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == inspector.inspection.selection }
        let next = current.map { min(max($0 + offset, 0), rows.count - 1) } ?? 0
        select(rows[next])
        if openRow != nil { openRow = rows[next].id }
    }

    /// A click on a row: selects it, and opens it on its parsed view, closing the
    /// one open; the open row clicked again closes.
    func toggle(_ row: Row) {
        let wasOpen = openRow == row.id
        select(row)
        openRow = wasOpen ? nil : row.id
    }

    /// Right, and Space on a closed row: the selected row opens.
    func openSelection() {
        guard let selection = inspector.inspection.selection, rows.contains(where: { $0.id == selection }) else { return }
        openRow = selection
    }

    /// Left, and Space on the open row: it closes.
    func closeOpenRow() {
        openRow = nil
    }

    /// Space: the selected row opens, or closes when it's the open one.
    func toggleSelection() {
        if openRow != nil, openRow == inspector.inspection.selection { closeOpenRow() } else { openSelection() }
    }

    /// Sorts the filtered Pattern's rows by `order` (the Inspector's order for
    /// its tab), keeping the selection.
    func sort(_ order: EntryOrder) {
        guard let filter else { return }
        inspector.setOrder(order, of: filter)
        updateRows()
    }

    private func updateRows() {
        // Plain Text's pieces only under its own chip: unfiltered, the list is Matches.
        // One Pattern's rows come in its tab's order, which may be sorted.
        let shown: [Row]
        if let filter, let tab = inspector.inspection.tab(filter), inspector.order(of: filter) != .position {
            shown = inspector.orderedIndices(of: tab).map { Row(id: EntryID(tab: filter, index: $0), entry: tab.entries[$0], tab: tab) }
        } else {
            shown = filter.map { tab in allRows.filter { $0.tab.id == tab } } ?? allRows.filter { $0.tab.id != .plainText }
        }
        rows = Array(shown.prefix(Self.largestList))
        hiddenRowCount = shown.count - rows.count
        // A filter whose Pattern is gone shows everything again.
        if rows.isEmpty, filter != nil, !allRows.isEmpty { filter = nil }
        // An open row a filter hides, or an edit took away, closes.
        if let openRow, !rows.contains(where: { $0.id == openRow }) { self.openRow = nil }
    }

    /// `old`'s Match in `rows`, after an edit: the one in its tab with its text,
    /// the nearest if it comes more than once (an edit before it moves it, which
    /// leaves its index pointing at another Match), or the one in its place when
    /// the edit was inside it. Nil when the edit took it away.
    private static func row(matching old: Row, in rows: [Row]) -> EntryID? {
        let range = old.entry.range
        let tab = rows.filter { $0.tab.id == old.tab.id }
        func apart(_ row: Row) -> Int { abs(row.entry.range.location - range.location) }
        let same = tab.filter { $0.entry.text == old.entry.text }
        let edited = tab.filter { NSIntersectionRange($0.entry.range, range).length > 0 }
        return (same.min { apart($0) < apart($1) } ?? edited.min { apart($0) < apart($1) })?.id
    }

    /// Every tab's entries (Plain Text's too), by where they start in the text, the
    /// longer first, so a Match comes before those inside it.
    private static func rows(of inspection: Inspection) -> [Row] {
        inspection.tabs
            .flatMap { tab in
                tab.entries.map { Row(id: EntryID(tab: tab.id, index: $0.index), entry: $0, tab: tab) }
            }
            .sorted {
                ($0.entry.range.location, -$0.entry.range.length) < ($1.entry.range.location, -$1.entry.range.length)
            }
    }

    private func showSelection() {
        guard let (entry, color) = inspector.selectedMatch else {
            preview.inspected = nil
            return
        }
        preview.inspected = (entry.range, color)
    }
}

/// The Selection Popover, in the Panel's look and made for quick work on what the
/// shortcut captured: a header, its first lines unwrapped with pills, then every
/// Match as one dense, collapsible list with a chip per Pattern to filter it. A
/// click on a row opens it on its parsed view (the Inspector's card, JSON
/// beautified), its buttons run its Actions, and the arrows, Space and Return work
/// the list; Esc closes it. Anything deeper is a Pop Out or the Panel away, in the
/// footer; Settings and Quit are in the menu bar icon's right-click menu.
struct SelectionPopoverView: View {
    let model: SelectionPopoverModel
    /// Opens the Panel as it is, from the footer when there's no text.
    let openPanel: () -> Void
    let close: () -> Void

    private var shortcut: String { AppConfig.store.config.shortcut.symbolText }

    /// Room for an open JSON card (`MatchCard.tallest`) with the open row and four
    /// or five more under the header, preview and chips; 700 pt with the arrow and
    /// the menu bar stays inside the 800 pt or so a 13" MacBook shows.
    static let size = CGSize(width: 460, height: 700)

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isTooLarge {
                ContentUnavailableView(
                    "Too long to inspect here", systemImage: "doc.text",
                    description: Text(model.isTooLargeForPanel
                        ? "It's over \(PanelModel.megabytes(PanelModel.largestInput)) MB, too large for the Panel too."
                        : "Open it in the Panel.")
                )
                .frame(maxHeight: .infinity)
            } else {
                // Editable: type or paste into it (its placeholder says so when empty).
                PreviewHost(view: model.preview)
                    .frame(height: model.previewHeight)
                    .mask(TrailingFade(width: 28))
                if model.hiddenLineCount > 0 {
                    Button {
                        model.openInPanel()
                    } label: {
                        Text("··· " + counted(model.hiddenLineCount, "more line"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Scroll the preview, or click to open all of it in the Panel")
                }
                Hairline()
                if model.text.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    FilterBar(model: model)
                    Hairline()
                    MatchList(model: model)
                        .frame(maxHeight: .infinity)
                }
            }
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(shortcuts)
        .onExitCommand(perform: close)
    }

    /// Settings' shortcut (⌘,) opens it, the popover closing behind it, and Quit's
    /// (⌘Q) quits, as from the menu bar icon's menu; the buttons are only there for
    /// their shortcuts, as the Config sets them.
    private var shortcuts: some View {
        let shortcuts = AppConfig.store.config.shortcuts
        return ZStack {
            if let settings = shortcuts[.settings]?.swiftUI {
                Button("Settings…") {
                    SettingsWindowController.show()
                    close()
                }
                .keyboardShortcut(settings)
            }
            if let quit = shortcuts[.quit]?.swiftUI {
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut(quit)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Before the first selection, or when the shortcut found none.
    @ViewBuilder private var emptyState: some View {
        if model.lacksAccessibility {
            ContentUnavailableView(
                "Accessibility is off", systemImage: "lock.shield",
                description: Text(
                    "textier copies your selection with ⌘C, which macOS allows only with Accessibility. "
                        + "Grant it in System Settings → Privacy & Security → Accessibility."
                )
            )
        } else {
            ContentUnavailableView(
                model.hasCaptured ? "Nothing selected" : "No selection yet", systemImage: "text.cursor",
                description: Text("Select text in any app and press \(shortcut), or paste or type it above.")
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Selection")
                    .font(.system(size: 13, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    Text(model.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.clear()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .disabled(!model.canClear)
            .help("Clear the selection")
            .accessibilityLabel("Clear")
            Button {
                model.inspector.highlighting.toggle()
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 26)
                    .foregroundStyle(model.inspector.highlighting ? .primary : .secondary)
                    .background(Capsule().fill(model.inspector.highlighting ? Color.primary.opacity(0.1) : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Tint Matches in the preview")
            .accessibilityLabel("Highlighting")
            if !AppConfig.store.warnings.isEmpty {
                WarningsBadge(warnings: AppConfig.store.warnings.map(\.message))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    /// Text for Open in Panel to take; without any, it opens the Panel as it is.
    private var hasText: Bool { !model.text.isEmpty || model.isTooLarge }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                if hasText { model.openInPanel() } else { openPanel() }
            } label: {
                HStack(spacing: 6) {
                    Text(hasText ? "Open in Panel" : "Open Panel")
                    Text(shortcut)
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isTooLargeForPanel)
            .help(hasText
                ? "Work on the selection in the Panel: edit it, Pop Out its Matches, see their details"
                : "Open the Panel as you left it")
            Spacer(minLength: 8)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.primary.opacity(0.035))
    }
}

/// The Pattern chips over the list, one per Pattern with its Glyph and Match
/// count, in the Panel's tab order. A click shows only that Pattern's Matches,
/// filled in its color; a second click shows them all again. Dragged onto another,
/// a chip takes its place, in the order the Panel's tabs keep too.
private struct FilterBar: View {
    let model: SelectionPopoverModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragged: InspectorTab.ID?
    @State private var dropTarget: InspectorTab.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.inspector.patternTabs, id: \.id) { tab in
                    let isSelected = model.filter == tab.id
                    FilterChip(
                        color: model.inspector.color(of: tab), isSelected: isSelected,
                        help: "\(tab.title): \(tab.matchCountText)" + (isSelected ? ", click for all" : "") + " — drag to move"
                    ) {
                        Image(systemName: tab.glyph.symbolName)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("\(tab.entries.count)").monospacedDigit()
                    } action: {
                        model.show(only: isSelected ? nil : tab.id)
                    }
                    .accessibilityLabel("\(tab.title), \(tab.matchCountText)")
                    .modifier(TabDragging(model: model.inspector, tab: tab, dragged: $dragged, dropTarget: $dropTarget))
                }
                // The text between Matches, last and not dragged, as in the Panel.
                if let plainText = model.inspector.inspection.tab(.plainText) {
                    let isSelected = model.filter == .plainText
                    FilterChip(
                        color: Palette.plainText, isSelected: isSelected,
                        help: "Plain Text: the text between Matches, \(counted(plainText.entries.count, "piece"))"
                            + (isSelected ? ", click for the Matches" : "")
                    ) {
                        Image(systemName: Glyph.plainText.symbolName)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("\(plainText.entries.count)").monospacedDigit()
                    } action: {
                        model.show(only: isSelected ? nil : .plainText)
                    }
                    .accessibilityLabel("Plain Text, \(counted(plainText.entries.count, "piece"))")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .overlay(alignment: .trailing) {
            // One Pattern's chip on: its rows can be sorted.
            if let filter = model.filter, let tab = model.inspector.inspection.tab(filter), let kind = tab.sortKind {
                SortMenu(kind: kind, order: model.inspector.order(of: filter)) { model.sort($0) }
                    .padding(.horizontal, 6)
                    .background(.background.opacity(0.9), in: Capsule())
                    .padding(.trailing, 6)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: model.filter)
    }
}

private struct FilterChip<Label: View>: View {
    let color: PatternColor
    let isSelected: Bool
    let help: String
    @ViewBuilder let label: Label
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { label }
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(Color(color, isSelected ? \.onSolid : \.text))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(color, isSelected ? \.solid : hovering ? \.strongTint : \.tint)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The Matches, one line each, the open one with its card under it. It takes the
/// arrow keys, Space and Return while the popover is open (Up and Down move, Right
/// opens, Left closes, Space toggles, Return runs the first Action), and keeps the
/// selected row in view, the open one at the top.
private struct MatchList: View {
    let model: SelectionPopoverModel
    @FocusState private var isFocused: Bool
    @State private var reveal = CardReveal()

    var body: some View {
        if model.rows.isEmpty {
            Text(model.inspector.isInspecting ? "Inspecting…" : "No Matches. Open it in the Panel to work on the text.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.rows) { row in
                            // Each row reads the selection itself, so a move redraws
                            // the rows shown rather than building the list again.
                            MatchRow(model: model, row: row) {
                                reveal.cardDidAppear(row.id, proxy: proxy)
                            }
                            .id(row.id)
                        }
                        if model.hiddenRowCount > 0 {
                            Button("\(counted(model.hiddenRowCount, "more Match")) — Open in Panel") {
                                model.openInPanel()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
                .mask(EdgeFade(top: 4, bottom: 10))
                .background(SelectionFollower(model: model, proxy: proxy, reveal: reveal))
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .accessibilityLabel("Matches")
            // Only on opening: text pasted into an empty preview keeps the keyboard.
            .onChange(of: model.focusRequests) { isFocused = true }
            .onKeyPress(.upArrow) {
                model.moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                model.openSelection()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                model.closeOpenRow()
                return .handled
            }
            .onKeyPress(.space) {
                model.toggleSelection()
                return .handled
            }
            .onKeyPress(.return) {
                model.inspector.runFirstAction()
                return .handled
            }
        }
    }
}

/// Scrolls the list to the selected row as the selection moves, a row opening to
/// the top so its card shows under it, and to the list's top for a new copy; apart
/// from the list, so none of it redraws it.
private struct SelectionFollower: View {
    let model: SelectionPopoverModel
    let proxy: ScrollViewProxy
    let reveal: CardReveal

    var body: some View {
        Color.clear
            .onChange(of: model.inspector.inspection.selection) { _, id in
                // An open row scrolls for itself.
                if let id, model.openRow == nil { proxy.scrollTo(id) }
            }
            .onChange(of: model.openRow) { _, id in
                // Into view first, as the lazy list builds a row only once in
                // sight; its card, laid out, scrolls it again (`CardReveal`).
                reveal.pending = id
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: model.newSelections) {
                if let first = model.rows.first { proxy.scrollTo(first.id, anchor: .top) }
            }
    }
}

/// The row just opened, scrolled to the top again once its card is laid out. The
/// first scroll goes by the list without the card, as the lazy list builds a row
/// only once in sight, so near the list's end it stops short, the card below the
/// fold. Only an opening scrolls: a card coming back into sight as the list
/// scrolls leaves it be.
@MainActor private final class CardReveal {
    var pending: EntryID?
    private var proxy: ScrollViewProxy?

    /// The open row's card appeared: after this layout pass, it scrolls to the top.
    func cardDidAppear(_ id: EntryID, proxy: ScrollViewProxy) {
        self.proxy = proxy
        RunLoop.main.perform { [self] in
            MainActor.assumeIsolated {
                guard pending == id else { return }
                pending = nil
                self.proxy?.scrollTo(id, anchor: .top)
            }
        }
    }
}

/// A Match on one line: a disclosure chevron, its Glyph in its color (a Color
/// Rule's included), what it is (its Summary, or its text: a URL's whole text, as
/// its host alone says too little), and, on hover or when selected, buttons for
/// its Actions, Copy among them. A click selects it, ringing its pill in the
/// preview, and opens it on its card, or closes it when open. Only the open row
/// builds a card.
private struct MatchRow: View {
    let model: SelectionPopoverModel
    let row: SelectionPopoverModel.Row
    /// Its card appeared, for the list to scroll it into view.
    let cardDidAppear: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: PatternColor { row.entry.color ?? model.inspector.color(of: row.tab) }
    private var isSelected: Bool { model.inspector.inspection.selection == row.id }
    private var isOpen: Bool { model.openRow == row.id }
    private func run(_ item: ActionBarItem) { model.run(item, on: row) }

    var body: some View {
        let isOpen = isOpen
        VStack(spacing: 3) {
            header(isOpen: isOpen)
            if isOpen {
                MatchCard(
                    entry: row.entry, readsAsUTC: Bindable(model.inspector).readsDatetimeAsUTC, accent: color
                )
                .padding(.bottom, 5)
                .onAppear(perform: cardDidAppear)
            }
        }
    }

    private func header(isOpen: Bool) -> some View {
        let title = title
        let color = color
        let isSelected = isSelected
        let isText = title == row.entry.preview || title == row.entry.text
        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isOpen ? AnyShapeStyle(Color(color, \.text)) : AnyShapeStyle(.tertiary))
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOpen)
                .frame(width: 10)
            Image(systemName: row.tab.glyph.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(color, \.text))
                .frame(width: 16)
            Text(title)
                .font(isText ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
                .foregroundStyle(isTinted ? Color(color, \.text) : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 2)
            Spacer(minLength: 4)
            if hovering || isSelected {
                ForEach(buttons, id: \.self) { item in
                    Button { run(item) } label: {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(item.title)
                    .accessibilityLabel(item.title)
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isTinted ? Color(color, \.tint) : hovering ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(row) }
        .onHover { hovering = $0 }
        .help(row.entry.tooltip)
        // VoiceOver doesn't hover: the Actions are on the row whether shown or not.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.tab.title): \(title)")
        .accessibilityValue(isOpen ? "expanded" : "collapsed")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { model.toggle(row) }
        .accessibilityAction(named: isOpen ? "Collapse" : "Expand") { model.toggle(row) }
        .accessibilityActions {
            ForEach(buttons, id: \.self) { item in
                Button(item.title) { run(item) }
            }
        }
    }

    private var title: String {
        if case .url = row.entry.detail { return row.entry.text }
        return row.entry.summary?.text(readsAsUTC: model.inspector.readsDatetimeAsUTC) ?? row.entry.preview
    }

    /// The row's Actions as buttons, as its Action bar in the Panel has them.
    private var buttons: [ActionBarItem] {
        row.entry.barItems(isPlainText: row.tab.id == .plainText, inMatchWindow: false)
    }

    /// The open row, or else the selected one: with a card open, a row selected by
    /// one of its buttons (a quick Copy) doesn't tint as a second open row.
    private var isTinted: Bool {
        isOpen || (isSelected && model.openRow == nil)
    }
}

/// An open row's parsed view: the Inspector's card for the entry, JSON opening on
/// its beautified text (Tree a click away). It's as tall as what it shows up to
/// `tallest`, then scrolls inside. The text views have no height of their own, so
/// JSON's and plain text's are worked out from their lines; the rows of a URL, a
/// datetime or a file path are measured.
struct MatchCard: View {
    let entry: InspectorEntry
    @Binding var readsAsUTC: Bool
    let accent: PatternColor

    /// The tallest a card gets, leaving the open row and a few more in sight.
    static let tallest: CGFloat = 320
    /// The card's width: the popover's, less the list's margins.
    static let width = SelectionPopoverView.size.width - 12

    var body: some View {
        let detail = EntryDetailView(entry: entry, readsAsUTC: $readsAsUTC, accent: accent, jsonMode: .raw)
        if let height = Self.height(of: entry) {
            detail.frame(height: height)
        } else {
            CappedHeight(tallest: Self.tallest) { detail }
        }
    }

    /// The height JSON or plain text needs, up to `tallest`; nil for the cards whose
    /// rows can be measured.
    static func height(of entry: InspectorEntry) -> CGFloat? {
        switch entry.detail {
        case .json(let value):
            // The toolbar and footer (58 pt) around the text and its 8 pt insets,
            // never so short the tree has no room.
            let line = NSLayoutManager().defaultLineHeight(for: JSONColoring.font)
            let available = Int((tallest - 74) / line) + 1
            let lines = jsonLines(of: value, columns: columns(JSONColoring.font, inset: 36 + 4 + 10), within: available)
            return min(max(74 + CGFloat(lines) * line, 150), tallest)
        case .text(let text) where entry.fields.isEmpty:
            // Plain Text's card: 12.5 pt monospaced, 3 pt between lines, 12 pt insets.
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let line = NSLayoutManager().defaultLineHeight(for: font) + 3
            let columns = columns(font, inset: 28)
            // Counted unit by unit, stopping once past the card's height: a Plain
            // Text piece can be most of a megabyte.
            var lines = 0, column = 0
            for unit in text.utf16 {
                guard unit == 10 else {
                    column += 1
                    continue
                }
                lines += max(1, (column + columns - 1) / columns)
                column = 0
                if CGFloat(lines) * line > tallest { return tallest }
            }
            lines += max(1, (column + columns - 1) / columns)
            return min(24 + CGFloat(lines) * line, tallest)
        default:
            return nil
        }
    }

    /// How many characters of `font` fit on a line of the card, past `inset`.
    private static func columns(_ font: NSFont, inset: CGFloat) -> Int {
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        return max(1, Int((width - inset) / advance))
    }

    /// The lines `value` takes beautified, wrapped at `columns`, counting no
    /// further than `limit`: a JSON entry may be most of a megabyte, and only
    /// whether it overflows the card matters past that.
    static func jsonLines(of value: JSONValue, columns: Int, within limit: Int) -> Int {
        var lines = 0
        func wrapped(_ length: Int) -> Int { max(1, (length + columns - 1) / columns) }
        // `lead` is what comes before the value on its line: indent, key, ": ".
        func count(_ value: JSONValue, lead: Int, indent: Int) {
            guard lines < limit else { return }
            switch value {
            case .object(let entries) where !entries.isEmpty:
                lines += wrapped(lead + 1)
                for entry in entries {
                    count(entry.value, lead: indent + 2 + entry.key.utf16.count + 4, indent: indent + 2)
                }
                lines += 1
            case .array(let elements) where !elements.isEmpty:
                lines += wrapped(lead + 1)
                for element in elements { count(element, lead: indent + 2, indent: indent + 2) }
                lines += 1
            case .string(let string): lines += wrapped(lead + string.utf16.count + 3)
            case .number(let source): lines += wrapped(lead + source.utf16.count + 1)
            default: lines += wrapped(lead + 6)
            }
        }
        count(value, lead: 0, indent: 0)
        return min(lines, limit)
    }
}

/// Its content as tall as it would be, up to `tallest`: a ScrollView of rows
/// offers its rows' height, and scrolls when that's more.
private struct CappedHeight: Layout {
    let tallest: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, tallest))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }
}

/// An opacity mask that fades its content out at the trailing edge, where the
/// preview's unwrapped lines run on.
private struct TrailingFade: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
        }
    }
}

/// The preview's text view, in a scroll view of its own.
private struct PreviewHost: NSViewRepresentable {
    let view: InputTextView

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PreviewScrollView()
        scrollView.documentView = view
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// The preview's scroll view. Three lines and "··· N more lines" say there's more
/// below; long lines scroll sideways, with a thin scroller over the text while
/// they do. It stays thin with a mouse attached or "Show scroll bars: Always" on,
/// where AppKit would put a full-size bar under the text.
final class PreviewScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = false
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        scrollerStyle = .overlay
        horizontalScroller?.controlSize = .small
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Always overlay: AppKit sets the system's style when it changes.
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

/// textier's menu bar icon and the Selection Popover under it, which the shortcut
/// opens with the selection, and a click on the icon opens with the last one. A
/// status item of textier's own, as SwiftUI's menu bar window can't be opened from
/// code. The icon turns into a warning sign while the config has problems.
@MainActor
final class SelectionPopoverController: NSObject, NSPopoverDelegate {
    let model = SelectionPopoverModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    /// Opens the Panel as it is, then closes the popover.
    private var openPanel: () -> Void = {}

    /// `openInPanel` opens text in the Panel; `openPanel` the Panel as it is. Then
    /// the popover closes, as a window opening from it wouldn't close it; the Panel
    /// opens first, so the closing doesn't hide textier for want of a window.
    init(openInPanel: @escaping (String) -> Void, openPanel: @escaping () -> Void) {
        super.init()
        model.onOpenInPanel = { [weak self] text in
            openInPanel(text)
            self?.close()
        }
        model.onClose = { [weak self] in self?.close() }
        self.openPanel = { [weak self] in
            openPanel()
            self?.close()
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: SelectionPopoverView(
            model: model,
            openPanel: { [weak self] in self?.openPanel() },
            close: { [weak self] in self?.close() }
        ))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        // A right-click (or a Control-click) shows the menu.
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    /// Shows what the shortcut captured, in the popover; false when the menu bar
    /// icon is out of sight (hidden past the notch, a full-screen app's menu bar, a
    /// menu bar set to hide itself), so the caller shows it in the Panel instead.
    func show(selection: String?, lacksAccessibility: Bool) -> Bool {
        model.show(selection: selection, lacksAccessibility: lacksAccessibility)
        guard isIconOnScreen else { return false }
        open()
        return true
    }

    var isShown: Bool { popover.isShown }

    func close() {
        popover.performClose(nil)
    }

    /// textier's glyph (`MenuBarGlyph`), or a warning sign while the config has
    /// problems.
    func updateIcon() {
        guard !AppConfig.store.warnings.isEmpty else {
            statusItem.button?.image = MenuBarGlyph.image
            return
        }
        let warning = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "textier: config warnings")
        warning?.isTemplate = true
        statusItem.button?.image = warning
    }

    func popoverDidShow(_ notification: Notification) {
        model.didOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        closedAt = Date()
        model.didClose(clearingAfter: TimeInterval(AppConfig.current.clearSelectionAfter))
        // Back to the app the selection came from, unless a textier window (the
        // Panel, a Match Window, Settings) is open to go back to.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            NSApp.hide(nil)
        }
    }

    /// When the popover last closed: a click on the icon while it's open closes it
    /// on the mouse-down (it's transient), and the click mustn't open it again.
    private var closedAt = Date.distantPast

    @objc private func toggle() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if popover.isShown {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            open()
        }
    }

    /// The menu bar icon's menu: the Panel, Settings, the config file and Quit,
    /// without opening the popover first.
    private func showMenu() {
        if popover.isShown { close() }
        // Set for this click only, so a left click still opens the popover.
        statusItem.menu = menu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let shortcuts = AppConfig.current.shortcuts
        func add(_ title: String, _ action: Selector, shortcut: Shortcut? = nil, enabled: Bool = true) {
            let equivalent = shortcut?.keyEquivalent
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: equivalent?.key ?? "")
            item.keyEquivalentModifierMask = equivalent?.modifiers ?? []
            item.target = self
            item.isEnabled = enabled
        }
        add("Show Selection", #selector(showPopover))
        add("Open Panel", #selector(openPanelFromMenu))
        add("Clear Selection", #selector(clearSelection), enabled: model.canClear)
        menu.addItem(.separator())
        add("Settings…", #selector(showSettings), shortcut: shortcuts[.settings])
        add("Open Config File", #selector(openConfigFile))
        add("Check for Updates…", #selector(checkForUpdates))
        menu.addItem(.separator())
        add("Quit", #selector(quit), shortcut: shortcuts[.quit])
        return menu
    }

    @objc private func showPopover() { open() }
    @objc private func openPanelFromMenu() { openPanel() }
    @objc private func clearSelection() { model.clear() }
    @objc private func showSettings() { SettingsWindowController.show() }
    @objc private func openConfigFile() { Editor.open(path: AppConfig.store.fileURL.path, line: nil) }
    @objc private func checkForUpdates() { Updater.shared.check(userInitiated: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func open() {
        guard let button = statusItem.button else { return }
        // The popover takes the keyboard, for the list's arrows and Return.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    /// Whether the icon is in the menu bar on a screen, not hidden by macOS.
    private var isIconOnScreen: Bool {
        guard let window = statusItem.button?.window, window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }
}
