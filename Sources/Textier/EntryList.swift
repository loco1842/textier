import AppKit
import SwiftUI
import TextierCore

/// The Inspector's rows: the selected tab's entries, or in the list layout every
/// group's header followed by its entries unless it's collapsed. An `NSTableView`
/// makes rows only for what's on screen and reuses them, so a tab with a hundred
/// thousand entries costs no more than one with ten; each row is the SwiftUI
/// `EntryRow` (or `SectionHeader`) in a reused cell.
///
/// The selected row draws its own tint in its Pattern's color, with a ring while
/// the list has keyboard focus. The arrows move the selection, Return or a
/// double-click runs the first Action, Tab and Shift-Tab go back to the Input, and
/// a click on a header collapses or expands its group.
struct EntryList: NSViewRepresentable {
    let model: PanelModel
    // What the list shows, passed in so SwiftUI updates it when one changes.
    let tabsRevision: Int
    let layout: InspectorLayout
    let collapsed: Set<InspectorTab.ID>
    let selection: EntryID?
    let readsAsUTC: Bool
    let listHasFocus: Bool

    func makeCoordinator() -> EntryListController { EntryListController(model: model) }

    func makeNSView(context: Context) -> NSScrollView { context.coordinator.scrollView }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(EntryListController.State(
            tabsRevision: tabsRevision, layout: layout, collapsed: collapsed, selection: selection,
            readsAsUTC: readsAsUTC, listHasFocus: listHasFocus
        ))
    }
}

@MainActor
final class EntryListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    /// What decides the rows and how they look.
    struct State: Equatable {
        var tabsRevision: Int
        var layout: InspectorLayout
        var collapsed: Set<InspectorTab.ID>
        var selection: EntryID?
        var readsAsUTC: Bool
        var listHasFocus: Bool

        /// In the tabs layout, the tab whose entries are the rows.
        var shownTab: InspectorTab.ID? { layout == .tabs ? selection?.tab : nil }
    }

    /// One row: a group's header, or an entry, by its tab's and its own index.
    enum Row: Equatable {
        case header(tab: Int)
        case entry(tab: Int, index: Int)
    }

    let scrollView = NSScrollView()
    let table = EntryTable()
    private let model: PanelModel
    private var state: State?
    private(set) var rows: [Row] = []
    /// Each tab's entries' rows, by entry index; nil for a tab whose entries
    /// aren't rows. A sorted tab's rows aren't in index order.
    private var entryRows: [[Int]?] = []
    /// Set while the list follows the model, so the table's own selection change
    /// isn't sent back to it.
    private var isFollowing = false

    init(model: PanelModel) {
        self.model = model
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // Rows draw their own selection, in their Pattern's color.
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(click)
        table.doubleAction = #selector(doubleClick)
        table.onReturn = { [weak model] in model?.runFirstAction() }
        table.onTab = { [weak model] in model?.focusInput() }
        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    // MARK: Following the model

    func update(_ next: State) {
        let previous = state
        state = next
        isFollowing = true
        defer { isFollowing = false }
        let structureChanged = previous == nil || previous?.tabsRevision != next.tabsRevision
            || previous?.layout != next.layout || previous?.collapsed != next.collapsed
            || previous?.shownTab != next.shownTab
        if structureChanged {
            rebuildRows(next)
            table.reloadData()
        } else if previous?.readsAsUTC != next.readsAsUTC {
            reloadVisibleRows()
        } else if previous?.selection != next.selection {
            // The two rows' text colors follow the selection.
            let changed = [previous?.selection, next.selection].compactMap { $0.flatMap(row(of:)) }
            table.reloadData(forRowIndexes: IndexSet(changed), columnIndexes: IndexSet(integer: 0))
        }
        if let row = next.selection.flatMap(row(of:)) {
            if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        if previous?.listHasFocus != next.listHasFocus, table.selectedRow >= 0 {
            table.rowView(atRow: table.selectedRow, makeIfNecessary: false)?.needsDisplay = true
        }
    }

    private func rebuildRows(_ state: State) {
        let tabs = model.inspection.tabs
        rows = []
        entryRows = Array(repeating: nil, count: tabs.count)
        func appendEntries(of tab: Int) {
            var byEntry = Array(repeating: 0, count: tabs[tab].entries.count)
            for index in model.orderedIndices(of: tabs[tab]) {
                byEntry[index] = rows.count
                rows.append(.entry(tab: tab, index: index))
            }
            entryRows[tab] = byEntry
        }
        switch state.layout {
        case .tabs:
            guard let shown = state.shownTab ?? tabs.first?.id, let tab = tabs.firstIndex(where: { $0.id == shown })
            else { return }
            appendEntries(of: tab)
        case .list:
            rows.reserveCapacity(tabs.reduce(tabs.count) { $0 + $1.entries.count })
            for (tab, group) in tabs.enumerated() {
                rows.append(.header(tab: tab))
                guard !state.collapsed.contains(group.id) else { continue }
                appendEntries(of: tab)
            }
        }
    }

    private func reloadVisibleRows() {
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)), columnIndexes: [0])
    }

    /// The row showing entry `id`, when it's one.
    private func row(of id: EntryID) -> Int? {
        let tabs = model.inspection.tabs
        guard let tab = tabs.firstIndex(where: { $0.id == id.tab }), let byEntry = entryRows[safe: tab] ?? nil
        else { return nil }
        return byEntry[safe: id.index]
    }

    private func entryID(at row: Int) -> EntryID? {
        guard case .entry(let tab, let index) = rows[safe: row] else { return nil }
        return EntryID(tab: model.inspection.tabs[tab].id, index: index)
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: SectionHeader.height + 2
        case .entry(let tab, let index): EntryRow.height(of: model.inspection.tabs[tab].entries[index])
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .entry = rows[row] { true } else { false }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isFollowing, let id = entryID(at: table.selectedRow) else { return }
        model.select(id)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: EntryRowView.identifier, owner: nil) as? EntryRowView ?? EntryRowView()
        view.identifier = EntryRowView.identifier
        view.hasFocusRing = { [weak self] in self?.state?.listHasFocus ?? false }
        if case .entry(let tab, let index) = rows[row] {
            let group = model.inspection.tabs[tab]
            view.color = group.entries[index].color ?? model.color(of: group)
        } else {
            view.color = nil
        }
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tabs = model.inspection.tabs
        switch rows[row] {
        case .header(let tab):
            let group = tabs[tab]
            let cell = hostingCell(HeaderCell.self, in: tableView)
            let id = group.id
            cell.host.rootView = SectionHeader(
                tab: group, color: model.color(of: group),
                isExpanded: Binding(
                    get: { [weak model] in !(model?.isCollapsed(id) ?? false) },
                    set: { [weak model] in model?.setCollapsed(id, !$0) }
                ),
                sorting: (model.order(of: id), { [weak model] in model?.setOrder($0, of: id) })
            )
            return cell
        case .entry(let tab, let index):
            let group = tabs[tab]
            let entry = group.entries[index]
            let cell = hostingCell(EntryCell.self, in: tableView)
            cell.host.rootView = EntryRow(
                entry: entry, color: entry.color ?? model.color(of: group),
                parentColor: entry.parent.map(model.color(ofParent:)),
                isSelected: state?.selection == EntryID(tab: group.id, index: index),
                readsAsUTC: state?.readsAsUTC ?? false
            )
            return cell
        }
    }

    private func hostingCell<Cell: HostingCell>(_ type: Cell.Type, in tableView: NSTableView) -> Cell {
        if let cell = tableView.makeView(withIdentifier: Cell.identifier, owner: nil) as? Cell { return cell }
        let cell = Cell()
        cell.identifier = Cell.identifier
        return cell
    }

    // MARK: Clicks

    /// A click on a header collapses or expands its group.
    @objc private func click() {
        guard case .header(let tab) = rows[safe: table.clickedRow] else { return }
        let id = model.inspection.tabs[tab].id
        model.setCollapsed(id, !model.isCollapsed(id))
    }

    @objc private func doubleClick() {
        guard entryID(at: table.clickedRow) != nil else { return }
        model.runFirstAction()
    }
}

/// The entry list's table: Return runs the selected entry's first Action, Tab and
/// Shift-Tab go back to the Input; the arrows are the table's own.
final class EntryTable: NSTableView {
    var onReturn: () -> Void = {}
    var onTab: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn()
        case 48: onTab()
        default: super.keyDown(with: event)
        }
    }
}

/// A row's background: the selected entry's tint in its color, rounded and inset,
/// with a ring in the solid color while the list has keyboard focus.
final class EntryRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("EntryRowView")
    var color: PatternColor?
    var hasFocusRing: () -> Bool = { false }

    override var isSelected: Bool {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isSelected, let color else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.pattern(color, \.tint).setFill()
        shape.fill()
        if hasFocusRing() {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 8.75, dy: 1.75), xRadius: 9.25, yRadius: 9.25)
            ring.lineWidth = 1.5
            NSColor.pattern(color, \.solid).setStroke()
            ring.stroke()
        }
    }

    // The table's own selection drawing is off; the background above is it.
    override func drawSelection(in dirtyRect: NSRect) {}
}

/// A table cell holding a SwiftUI view, reused from row to row.
class HostingCell: NSTableCellView {
    class var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("HostingCell") }
}

final class EntryCell: HostingCell {
    override class var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("EntryCell") }
    let host = NSHostingView(rootView: EntryRow.placeholder)

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class HeaderCell: HostingCell {
    override class var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("HeaderCell") }
    let host = NSHostingView(rootView: SectionHeader.placeholder)

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        // The header sits 2 pt below the row's top, as it did in the list.
        host.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 2))
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension EntryRow {
    /// What a new cell holds until the table gives it a row.
    static var placeholder: EntryRow {
        EntryRow(
            entry: InspectorEntry(wholeText: "", actions: []), color: Palette.fallback, parentColor: nil,
            isSelected: false, readsAsUTC: false
        )
    }
}

extension SectionHeader {
    static var placeholder: SectionHeader {
        SectionHeader(
            tab: InspectorTab(id: .plainText, title: "", color: nil, glyph: .plainText, entries: []),
            color: Palette.plainText, isExpanded: .constant(true)
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
