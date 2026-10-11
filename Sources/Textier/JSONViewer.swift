import AppKit
import TextierCore

/// One row of the JSON Viewer: a value and how it was reached from its parent.
///
/// Children are built lazily and cached, so the outline view sees stable items. A
/// string holding escaped JSON (while the `escaped-json` Pattern is enabled) has the
/// parsed JSON's entries as its children: expanding the node is parsing it inline,
/// collapsing it goes back to the string, and nested escaped JSON works the same way
/// one level down.
@MainActor
final class JSONNode {
    /// How the parent reaches this node; nil for the root.
    let component: JSONPathComponent?
    /// The value as it appears in the source JSON.
    let value: JSONValue
    weak var parent: JSONNode?
    let depth: Int
    private var cachedChildren: [JSONNode]?
    private var cachedStringMatch: Match??
    private var cachedPairedLine: Int??
    private var cachedEscapedJSON: JSONValue??

    init(value: JSONValue, component: JSONPathComponent? = nil, parent: JSONNode? = nil) {
        self.value = value
        self.component = component
        self.parent = parent
        depth = (parent?.depth ?? -1) + 1
    }

    /// The JSON this string value holds, while `escaped-json` is enabled in the
    /// current Config. Parsed once; the enabled check is live, so a reload that
    /// disables the Pattern takes the affordance away.
    var escapedJSON: JSONValue? {
        guard AppConfig.current.escapedJSONPattern != nil else { return nil }
        if let cachedEscapedJSON { return cachedEscapedJSON }
        let parsed = value.escapedJSON
        cachedEscapedJSON = .some(parsed)
        return parsed
    }

    /// What the node shows: `value`, or the JSON a string holds once parsed inline
    /// (`parsedInline` is whether the outline view has the node expanded).
    func content(parsedInline: Bool) -> JSONValue {
        parsedInline ? escapedJSON ?? value : value
    }

    /// The object or array whose entries are the node's children: the value, or the
    /// JSON a string holds.
    private var container: JSONValue? {
        value.isContainer ? value : escapedJSON
    }

    var children: [JSONNode] {
        guard let container else { return [] }
        if let cachedChildren { return cachedChildren }
        let built: [JSONNode] = switch container {
        case .object(let entries):
            entries.map { JSONNode(value: $0.value, component: .key($0.key), parent: self) }
        case .array(let elements):
            elements.enumerated().map { JSONNode(value: $1, component: .index($0), parent: self) }
        default:
            []
        }
        cachedChildren = built
        return built
    }

    var keyPathString: String {
        var components: [JSONPathComponent] = []
        var node: JSONNode? = self
        while let current = node, let component = current.component {
            components.insert(component, at: 0)
            node = current.parent
        }
        return keyPath(components)
    }

    /// The path bar's steps from the root to here: `$`, then each key (after a dot)
    /// or index (`[0]`), each with its node.
    var pathSteps: [(separator: String, label: String, node: JSONNode)] {
        var steps: [(separator: String, label: String, node: JSONNode)] = []
        var current: JSONNode? = self
        while let step = current {
            if let component = step.component {
                let label = keyPath([component])
                steps.insert((label.hasPrefix("[") ? "" : ".", label, step), at: 0)
            } else {
                steps.insert(("", "$", step), at: 0)
            }
            current = step.parent
        }
        return steps
    }

    /// The key as the user reads it: the object key, or the array index.
    var keyText: String {
        switch component {
        case .key(let key): key
        case .index(let index): String(index)
        case nil: ""
        }
    }

    /// The Match a string value is in its entirety (a URL or a file path), whose
    /// Actions the node offers. Detected once per Config: `forgetStringMatches()`
    /// after a reload.
    var stringMatch: Match? {
        if let cachedStringMatch { return cachedStringMatch }
        var match: Match?
        if case .string(let string) = value { match = stringValueMatch(string, config: AppConfig.current) }
        cachedStringMatch = .some(match)
        return match
    }

    /// The line a backtrace frame's `file` value takes from its sibling `line` key
    /// (`pairedLine(in:config:)`), when this node is its object's first `file`
    /// entry. Worked out once per Config, like `stringMatch`.
    var pairedLine: Int? {
        if let cachedPairedLine { return cachedPairedLine }
        var line: Int?
        if case .key("file") = component, let parent, case .object(let entries)? = parent.container,
           parent.children.first(where: { $0.component == .key("file") }) === self {
            line = TextierCore.pairedLine(in: entries, config: AppConfig.current)
        }
        cachedPairedLine = .some(line)
        return line
    }

    /// Drops the cached string Matches and paired lines of this node and every
    /// built descendant.
    func forgetStringMatches() {
        cachedStringMatch = nil
        cachedPairedLine = nil
        cachedChildren?.forEach { $0.forgetStringMatches() }
    }
}

/// The JSON Viewer: an order-preserving tree of a JSON value. It has no menus: the
/// selected node's actions live in the node toolbar above it (`NodeToolbar`).
///
/// A URL or file path value is drawn as a link; double-clicking it runs its first
/// Action, and double-clicking elsewhere toggles a node. A string holding escaped
/// JSON shows a `{…}` badge and a disclosure triangle: expanding it (triangle,
/// double-click or Parse Inline) shows the parsed JSON in its place, collapsing it
/// (or Show as String) goes back to the string. Values are colored with the
/// syntax-coloring theme for the current appearance.
@MainActor
final class JSONViewer: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let root: JSONNode
    let outlineView = NSOutlineView()
    private(set) lazy var scrollView = makeScrollView()
    /// Called with the selected node, or nil.
    var onSelectionChange: (JSONNode?) -> Void = { _ in }
    /// Called after a node expands or collapses.
    var onExpansionChange: () -> Void = {}
    private var isExpandingOnOpen = false
    /// Where string values under it show as `~/…` (display only: tooltips, copies
    /// and Actions keep the full path).
    var homeDirectory = NSHomeDirectory()
    /// The color search matches are tinted with: the Pattern's.
    var accent: PatternColor = Palette.fallback

    private static let column = NSUserInterfaceItemIdentifier("node")

    init(value: JSONValue) {
        root = JSONNode(value: value)
        super.init()
    }

    private func makeScrollView() -> NSScrollView {
        // One column of `key: value` rows, as JSON reads, with the type at the right.
        let column = NSTableColumn(identifier: Self.column)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.rowHeight = Self.rowHeight
        outlineView.outlineTableColumn = column
        outlineView.indentationPerLevel = Self.indentation
        outlineView.style = .plain
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.headerView = nil
        // It sits on the Inspector's card, as the other parsed views do.
        outlineView.backgroundColor = .clear
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rowDoubleClicked(_:))

        // The column takes the card's width; long values end in "…" (the selected
        // one wraps), so nothing runs past the card's edge.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // The first level's triangles sit a little in from the card's edge.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        scrollView.documentView = outlineView

        outlineView.reloadData()
        // Built while SwiftUI renders, so the open expansion mustn't report as a change.
        isExpandingOnOpen = true
        expandOnOpen([root])
        isExpandingOnOpen = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(configDidReload), name: ConfigStore.didReload, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnsDidResize), name: NSTableView.columnDidResizeNotification, object: outlineView
        )
        // The column follows the card's width without a column notification.
        outlineView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnsDidResize), name: NSView.frameDidChangeNotification, object: outlineView
        )
        return scrollView
    }

    /// Expands nodes per the open rule (depth 2, long arrays collapsed), top down.
    /// Escaped JSON starts as its string.
    private func expandOnOpen(_ nodes: [JSONNode]) {
        for node in nodes where node.value.isExpandedOnOpen(atDepth: node.depth) {
            outlineView.expandItem(node)
            expandOnOpen(node.children)
        }
    }

    /// A reload can change which strings are links and, by enabling or
    /// disabling `escaped-json`, which strings have children, so the tree is
    /// reloaded, keeping what was expanded where it still can be.
    @objc private func configDidReload() {
        root.forgetStringMatches()
        shownChildren = [:]
        let expanded = (0..<outlineView.numberOfRows).compactMap { row in
            (outlineView.item(atRow: row) as? JSONNode).flatMap { outlineView.isItemExpanded($0) ? $0 : nil }
        }
        outlineView.reloadData()
        for node in expanded where !node.children.isEmpty {
            outlineView.expandItem(node)
        }
        onSelectionChange(selectedNode)
    }

    var selectedNode: JSONNode? {
        outlineView.item(atRow: outlineView.selectedRow) as? JSONNode
    }

    // MARK: Node actions

    /// Selects `node` (from the path bar) and scrolls to it.
    func select(_ node: JSONNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    /// Opens every object and array, at once. Escaped JSON stays a string: opening
    /// it would parse it inline.
    func expandAll() {
        func expand(_ node: JSONNode) {
            guard node.value.isContainer, !visibleChildren(of: node).isEmpty else { return }
            outlineView.expandItem(node)
            visibleChildren(of: node).forEach(expand)
        }
        Motion.instantly {
            expand(root)
        }
    }

    /// Closes everything under the root, at once.
    func collapseAll() {
        Motion.instantly {
            for child in visibleChildren(of: root) { outlineView.collapseItem(child, collapseChildren: true) }
        }
    }

    /// Whether an escaped-JSON string is expanded, showing the parsed JSON.
    func isParsedInline(_ node: JSONNode) -> Bool {
        !node.value.isContainer && outlineView.isItemExpanded(node)
    }

    /// Parse Inline, or Show as String.
    func toggleInline(_ node: JSONNode) {
        isParsedInline(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
    }

    /// Copy Value: what the node shows, so parsed escaped JSON copies as pretty JSON.
    func copyValue(of node: JSONNode) {
        copyToPasteboard(node.content(parsedInline: isParsedInline(node)).copyText)
    }

    /// Copy with Line: a paired `file` value as `path:line`.
    func copyWithLine(of node: JSONNode) {
        guard let line = node.pairedLine, case .string(let path) = node.value else { return }
        copyToPasteboard("\(path):\(line)")
    }

    // MARK: Expansion

    /// A row's text changes as it expands and collapses: a container between its
    /// preview and its size, an escaped-JSON string between the string and the
    /// parsed JSON's size.
    func outlineViewItemDidExpand(_ notification: Notification) {
        refreshRow(of: notification.userInfo?["NSObject"])
        if !isExpandingOnOpen { onExpansionChange() }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        refreshRow(of: notification.userInfo?["NSObject"])
        if !isExpandingOnOpen { onExpansionChange() }
    }

    /// The selected row wraps its whole value; the one before goes back to a line.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let before = wrappedNode.map { outlineView.row(forItem: $0) }
        wrappedNode = selectedNode
        let rows = IndexSet([before, outlineView.selectedRow].compactMap { $0 }.filter { $0 >= 0 })
        outlineView.reloadData(forRowIndexes: rows, columnIndexes: [0])
        measureWrappedRow()
        // AppKit animates a row height change; not under Reduce Motion.
        Motion.animate(0.15) { outlineView.noteHeightOfRows(withIndexesChanged: rows) }
        onSelectionChange(selectedNode)
    }

    private func refreshRow(of item: Any?) {
        guard let node = item as? JSONNode else { return }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.reloadData(forRowIndexes: [row], columnIndexes: [0])
        if row == outlineView.selectedRow {
            measureWrappedRow()
            Motion.animate(0.2) { outlineView.noteHeightOfRows(withIndexesChanged: [row]) }
        }
    }

    // MARK: Data source

    private func node(_ item: Any?) -> JSONNode {
        (item as? JSONNode) ?? root
    }

    /// The root is a row of its own, so the open rule applies to it too: a root
    /// array longer than the threshold starts collapsed.
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard item != nil else { return isSearching && searchShown.isEmpty ? 0 : 1 }
        return visibleChildren(of: node(item)).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        item == nil ? root : visibleChildren(of: node(item))[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !visibleChildren(of: node(item)).isEmpty
    }

    // MARK: Row heights

    private static let rowHeight: CGFloat = 22
    private static let indentation: CGFloat = 16
    /// The selected row's value wraps to at most this many lines, then ends in "…".
    static let maximumValueLines = 6
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: JSONColoring.font)

    /// The selected node, whose row's text wraps; and how many lines it wraps to.
    private weak var wrappedNode: JSONNode?
    private var wrappedLines = 1
    private var wrappedRow: Int? {
        wrappedNode.map { outlineView.row(forItem: $0) }.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// How many lines a node's row takes: one, or, for the selected row, as many as
    /// its text wraps to in its cell, up to the limit.
    func lineCount(of node: JSONNode) -> Int {
        node === wrappedNode ? wrappedLines : 1
    }

    /// Measures the selected row's text at its cell's width.
    private func measureWrappedRow() {
        wrappedLines = 1
        guard let row = wrappedRow, row < outlineView.numberOfRows,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? JSONRowCell
        else { return }
        cell.layoutSubtreeIfNeeded()
        let width = cell.label.frame.width
        guard width > 0 else { return }
        Self.measuringCell.attributedStringValue = cell.label.attributedStringValue
        let height = Self.measuringCell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height
        wrappedLines = min(Self.maximumValueLines, max(1, Int((height / Self.lineHeight - 0.25).rounded(.up))))
    }

    /// Wraps text as the selected row's label does, to count its lines.
    private static let measuringCell: NSTextFieldCell = {
        let cell = NSTextFieldCell(textCell: "")
        cell.wraps = true
        cell.lineBreakMode = .byCharWrapping
        cell.isBordered = false
        cell.isBezeled = false
        return cell
    }()

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        Self.rowHeight + CGFloat(lineCount(of: node(item)) - 1) * Self.lineHeight
    }

    /// A narrower or wider card rewraps the selected row. The outline resizes before
    /// it stretches its column, and lays out between, so it's measured again once
    /// the run loop turns, at the column's new width.
    @objc private func columnsDidResize() {
        guard !isRowHeightUpdatePending, wrappedRow != nil else { return }
        isRowHeightUpdatePending = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Cleared first: a selection gone meanwhile mustn't leave it stuck.
                self.isRowHeightUpdatePending = false
                guard let row = self.wrappedRow, row < self.outlineView.numberOfRows else { return }
                self.measureWrappedRow()
                Motion.instantly {
                    self.outlineView.noteHeightOfRows(withIndexesChanged: [row])
                }
            }
        }
    }

    private var isRowHeightUpdatePending = false

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ThemedRowView()
    }

    /// How far right of a disclosure triangle's center its row's cell starts,
    /// measured once on a row that has one.
    private var triangleToCell: CGFloat {
        if let cached = cachedTriangleToCell { return cached }
        guard let row = (0..<outlineView.numberOfRows).first(where: { outlineView.frameOfOutlineCell(atRow: $0).width > 0 })
        else { return Self.indentation / 2 }
        let measured = outlineView.frameOfCell(atColumn: 0, row: row).minX - outlineView.frameOfOutlineCell(atRow: row).midX
        cachedTriangleToCell = measured
        return measured
    }

    private var cachedTriangleToCell: CGFloat?

    /// The row view draws the lines down each open level it sits in.
    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let rowView = rowView as? ThemedRowView else { return }
        let level = outlineView.level(forRow: row)
        // Under each parent's disclosure triangle: measured from where this row's cell
        // starts, the same at a level whether or not the row has a triangle itself.
        let triangle = outlineView.frameOfCell(atColumn: 0, row: row).minX - triangleToCell
        rowView.guides = (0..<level).map { (triangle - CGFloat(level - $0) * Self.indentation).rounded(.down) }
        rowView.isMatch = (outlineView.item(atRow: row) as? JSONNode).map { searchMatches.contains(ObjectIdentifier($0)) } ?? false
        rowView.accent = NSColor(patternColor: accent, role: \.solid)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = outlineView.makeView(withIdentifier: Self.column, owner: self) as? JSONRowCell ?? JSONRowCell()
        cell.identifier = Self.column
        let node = node(item)
        cell.show(text(of: node), wrapping: node === wrappedNode)
        cell.label.toolTip = toolTip(of: node)
        let mark = typeName(of: node)
        // The quote is small at the others' size, and sits high: larger, and lowered.
        var attributes: [NSAttributedString.Key: Any] = mark == "”"
            ? [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .baselineOffset: -5]
            : [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]
        attributes[.foregroundColor] = NSColor.themeSecondaryForeground
        cell.typeLabel.attributedStringValue = NSAttributedString(string: mark, attributes: attributes)
        cell.typeLabel.toolTip = typeTitle(of: node)
        return cell
    }

    // MARK: Row text

    /// The value's type as a mark: how JSON writes an object and an array, a closing
    /// quote for a string, `#` for a number, a half-filled circle for on/off, `∅` for
    /// null.
    private func typeName(of node: JSONNode) -> String {
        switch node.content(parsedInline: isParsedInline(node)) {
        case .object: "{}"
        case .array: "[]"
        case .string: "”"
        case .number: "#"
        case .bool: "◐"
        case .null: "∅"
        }
    }

    /// The type's name, for the mark's tooltip and VoiceOver.
    private func typeTitle(of node: JSONNode) -> String {
        switch node.content(parsedInline: isParsedInline(node)) {
        case .object: "Object"
        case .array: "Array"
        case .string: "String"
        case .number: "Number"
        case .bool: "Boolean"
        case .null: "Null"
        }
    }

    /// `key: value` in the theme's colors: the key (an index or "root" muted), and
    /// the value, a container as its preview (collapsed) or size (open).
    func text(of node: JSONNode) -> NSAttributedString {
        let text = NSMutableAttributedString()
        func add(_ string: String, _ color: NSColor, _ extra: [NSAttributedString.Key: Any] = [:]) {
            text.append(NSAttributedString(
                string: string,
                attributes: [.font: JSONColoring.font, .foregroundColor: color].merging(extra) { $1 }
            ))
        }
        switch node.component {
        case .key(let key): add(key, JSONColoring.color(for: .key))
        case .index(let index): add(String(index), .themeSecondaryForeground)
        case nil: add("root", .themeSecondaryForeground)
        }
        // The root has no key of its own, so no colon after its name.
        add(node === root ? "  " : ": ", .themeSecondaryForeground)

        let parsedInline = isParsedInline(node)
        let content = node.content(parsedInline: parsedInline)
        switch content {
        case .object, .array:
            if outlineView.isItemExpanded(node) {
                add(content.openSummary + (parsedInline ? " parsed from string" : ""), .themeSecondaryForeground)
            } else if let preview = content.collapsedPreview {
                // The braces muted, what's inside them in the text color.
                add(String(preview.prefix(2)), .themeSecondaryForeground)
                add(String(preview.dropFirst(2).dropLast(2)), .themeForeground)
                add(String(preview.suffix(2)), .themeSecondaryForeground)
            }
        case .string(let string):
            let stringColor = JSONColoring.color(for: .string)
            if node.escapedJSON != nil {
                add("{…} ", .controlAccentColor, [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)])
            }
            // Every line break (CRLF as one) as ⏎: the label would end the row at it.
            let shown = String(shortened(Self.capped(string)).map { $0.isNewline ? "⏎" : $0 })
            add(shown, stringColor, node.stringMatch != nil ? [.underlineStyle: NSUnderlineStyle.single.rawValue] : [:])
        case .number(let source):
            add(source, JSONColoring.color(for: .number))
        case .bool(let bool):
            add(bool ? "true" : "false", JSONColoring.color(for: .boolean))
        case .null:
            add("null", JSONColoring.color(for: .null))
        }
        return text
    }

    /// A path under the home directory as `~/…`.
    private func shortened(_ string: String) -> String {
        let home = homeDirectory.hasSuffix("/") ? homeDirectory : homeDirectory + "/"
        return string.hasPrefix(home) ? "~/" + string.dropFirst(home.count) : string
    }

    /// The longest a string value shows in its row and tooltip.
    static let shownCharacters = 2_000

    /// A string's first `shownCharacters` characters, then "…" when there's more. A
    /// row shows six lines at most, and laying out a multi-megabyte value for them
    /// stalls every redraw. Copies, Actions and the search keep the whole value.
    private static func capped(_ string: String) -> String {
        let start = string.prefix(shownCharacters + 1)
        return start.count > shownCharacters ? String(start.dropLast()) + "…" : string
    }

    /// The value (its start, when it's long), with what a double-click does.
    private func toolTip(of node: JSONNode) -> String? {
        guard case .string(let value) = node.value else { return nil }
        let string = Self.capped(value)
        if node.escapedJSON != nil {
            return "Escaped JSON: expand or double-click to parse it inline\n\n" + string
        }
        if let action = node.stringMatch?.actions.first {
            let atLine = action == .openFile ? node.pairedLine.map { " at line \($0)" } ?? "" : ""
            return "Double-click: \(action.title)\(atLine)\n\n" + string
        }
        return string
    }

    // MARK: Search

    /// What the tree is filtered by; empty shows everything.
    private(set) var query = ""
    /// Nodes matching the search, for the row tint and the count.
    private(set) var searchMatches: Set<ObjectIdentifier> = []
    /// Nodes shown while searching: the matches and the containers they're in.
    private var searchShown: Set<ObjectIdentifier> = []
    /// What was open and selected before the search began, back when it's cleared.
    private var openBeforeSearch: [JSONNode]?
    private weak var selectedBeforeSearch: JSONNode?
    /// Called after the search changes what's shown.
    var onSearchChange: () -> Void = {}
    /// Why a `$` query can't be read; the tree stays as the last search left it
    /// meanwhile, so it doesn't jump while a query is being typed.
    private(set) var searchError: String?
    /// A `$` query's results, in document order, for Copy Results.
    private(set) var pathResults: [JSONNode] = []
    /// Whether the tree is filtered by a search.
    private(set) var isSearching = false
    /// Each shown container's children as the search shows them, worked out once
    /// per search: the outline asks for them child by child.
    private var shownChildren: [ObjectIdentifier: [JSONNode]] = [:]

    var isPathQuery: Bool { query.hasPrefix("$") }
    var matchCount: Int { searchMatches.count }

    /// Filters the tree to what `query` finds and the containers leading to it,
    /// opened to show it: a `$` query's results (JSONPath), or else the nodes whose
    /// key or value contains the text (`jsonSearchMatches`). A found object or array
    /// shows closed, and opens to all of it. It doesn't look inside escaped JSON
    /// (opening that would parse it inline). Clearing it shows the whole tree again,
    /// opened as it was, keeping the selection where it can.
    func search(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query != self.query else { return }
        var results: [JSONPathResult] = []
        if query.hasPrefix("$") {
            do {
                results = try JSONPathQuery(query).evaluate(root.value)
            } catch {
                self.query = query
                searchError = error.message
                onSearchChange()
                return
            }
        }
        searchError = nil
        // Cleared while nothing was filtered (only a broken query was typed): the
        // tree is already as it should be.
        if !isSearching, query.isEmpty {
            self.query = query
            onSearchChange()
            return
        }
        if !isSearching {
            openBeforeSearch = openNodes()
            selectedBeforeSearch = selectedNode
        }
        // Cleared, the row selected during the search stays, or else the one before.
        let selected = selectedNode ?? (query.isEmpty ? selectedBeforeSearch : nil)
        if query.isEmpty { selectedBeforeSearch = nil }
        self.query = query
        isSearching = !query.isEmpty
        searchMatches = []
        searchShown = []
        shownChildren = [:]
        pathResults = []
        if query.hasPrefix("$") {
            for result in results {
                guard let node = node(at: result) else { continue }
                pathResults.append(node)
                searchMatches.insert(ObjectIdentifier(node))
                var step: JSONNode? = node
                while let current = step, searchShown.insert(ObjectIdentifier(current)).inserted {
                    step = current.parent
                }
            }
        } else if !query.isEmpty {
            collectMatches(in: root)
        }

        isExpandingOnOpen = true
        Motion.instantly {
            outlineView.reloadData()
            // The outline keeps what was open across a reload; start from closed.
            outlineView.collapseItem(nil, collapseChildren: true)
            if !isSearching {
                for node in openBeforeSearch ?? [] { outlineView.expandItem(node) }
                if query.isEmpty { openBeforeSearch = nil }
            } else {
                openShown(root)
            }
        }
        isExpandingOnOpen = false
        let row = selected.map { outlineView.row(forItem: $0) } ?? -1
        outlineView.selectRowIndexes(row >= 0 ? [row] : [], byExtendingSelection: false)
        if row >= 0 { outlineView.scrollRowToVisible(row) }
        // Reloading drops a selection the search hides without a selection change,
        // and putting it back may not post one either: say what's selected now.
        if wrappedNode !== selectedNode {
            wrappedNode = selectedNode
            measureWrappedRow()
            if let row = wrappedRow { outlineView.noteHeightOfRows(withIndexesChanged: [row]) }
        }
        onSelectionChange(selectedNode)
        onSearchChange()
    }

    /// Marks the nodes under `node` the search finds, and those leading to them;
    /// whether `node` is shown.
    @discardableResult
    private func collectMatches(in node: JSONNode) -> Bool {
        var shown = false
        if node.value.isContainer {
            for child in node.children where collectMatches(in: child) { shown = true }
        }
        let key: String? = node === root ? nil : node.keyText
        if jsonSearchMatches(key: key, value: node.value, query: query) {
            searchMatches.insert(ObjectIdentifier(node))
            shown = true
        }
        if shown { searchShown.insert(ObjectIdentifier(node)) }
        return shown
    }

    /// Opens the containers that lead to matches, top down; a match itself stays
    /// closed unless more matches are inside it.
    private func openShown(_ node: JSONNode) {
        let leading = visibleChildren(of: node).filter { searchShown.contains(ObjectIdentifier($0)) }
        guard !leading.isEmpty, searchShown.contains(ObjectIdentifier(node)) else { return }
        outlineView.expandItem(node)
        leading.forEach(openShown)
    }

    /// The node a `$` query's result is, from the root. A node's children are its
    /// entries or elements in order, so each step is the child at its ordinal: an
    /// object with a key twice gives the entry the query found.
    private func node(at result: JSONPathResult) -> JSONNode? {
        var node = root
        for (component, ordinal) in zip(result.path, result.ordinals) {
            let children = node.children
            guard children.indices.contains(ordinal), children[ordinal].component == component else { return nil }
            node = children[ordinal]
        }
        return node
    }

    /// Whether `node` is a match or inside one, so all of it shows.
    private func isWithinMatch(_ node: JSONNode) -> Bool {
        var step: JSONNode? = node
        while let current = step {
            if searchMatches.contains(ObjectIdentifier(current)) { return true }
            step = current.parent
        }
        return false
    }

    /// Copy Results: what a `$` query found, as a JSON array.
    func copyResults() {
        copyToPasteboard(JSONValue.array(pathResults.map(\.value)).prettyPrinted)
    }

    /// The expanded nodes, in row order (so parents come before children).
    private func openNodes() -> [JSONNode] {
        (0..<outlineView.numberOfRows).compactMap { row in
            (outlineView.item(atRow: row) as? JSONNode).flatMap { outlineView.isItemExpanded($0) ? $0 : nil }
        }
    }

    /// A node's children as the tree shows them: all of them, or while searching,
    /// those the search shows. The search doesn't look inside escaped JSON, but a
    /// shown string is a match or inside one, so it can still be parsed inline.
    private func visibleChildren(of node: JSONNode) -> [JSONNode] {
        guard isSearching else { return node.children }
        guard node.value.isContainer else { return isWithinMatch(node) ? node.children : [] }
        if let cached = shownChildren[ObjectIdentifier(node)] { return cached }
        let shown = isWithinMatch(node) ? node.children : node.children.filter { searchShown.contains(ObjectIdentifier($0)) }
        shownChildren[ObjectIdentifier(node)] = shown
        return shown
    }

    // MARK: Clicks

    @objc private func rowDoubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? JSONNode else { return }
        doubleClick(node)
    }

    /// A link value runs its first Action (a paired `file` value at its line); any
    /// other expandable node toggles.
    func doubleClick(_ node: JSONNode) {
        if let match = node.stringMatch, let action = match.actions.first {
            action.perform(on: match, pairedLine: node.pairedLine)
        } else if outlineView.isExpandable(node) {
            outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
        }
    }
}

/// A JSON Viewer row: `key: value` on one line, ending in "…", or wrapped
/// anywhere over a few lines when selected, with the value's type at the right.
final class JSONRowCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let typeLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        for field in [label, typeLabel] {
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        textField = label
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.cell?.truncatesLastVisibleLine = true
        typeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        typeLabel.alignment = .center
        typeLabel.toolTip = nil
        typeLabel.textColor = .themeSecondaryForeground
        typeLabel.alphaValue = 0.75
        typeLabel.setContentHuggingPriority(.required, for: .horizontal)
        typeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = (22 - NSLayoutManager().defaultLineHeight(for: JSONColoring.font)) / 2
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.topAnchor.constraint(equalTo: topAnchor, constant: top),
            typeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            typeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            typeLabel.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows `text` on one line, or wrapped over up to the viewer's line limit.
    func show(_ text: NSAttributedString, wrapping: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrapping ? .byCharWrapping : .byTruncatingTail
        let styled = NSMutableAttributedString(attributedString: text)
        styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
        label.maximumNumberOfLines = wrapping ? JSONViewer.maximumValueLines : 1
        label.cell?.wraps = wrapping
        label.lineBreakMode = paragraph.lineBreakMode
        label.attributedStringValue = styled
    }
}

/// A JSON Viewer row, selected in the theme's colors rather than the system's
/// (a wash of its foreground, the text keeping its token colors), tinted in the
/// Pattern's color when the search finds it, with faint lines down the open levels
/// it sits in.
final class ThemedRowView: NSTableRowView {
    /// Where the level lines run, in the row's coordinates.
    var guides: [CGFloat] = [] { didSet { needsDisplay = true } }
    @objc var guideCount: Int { guides.count }
    @objc var isMatch = false { didSet { needsDisplay = true } }
    var accent: NSColor = .controlAccentColor

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isMatch {
            accent.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        NSColor.themeSecondaryForeground.withAlphaComponent(0.25).setFill()
        for x in guides {
            NSRect(x: x.rounded(.down), y: bounds.minY, width: 1, height: bounds.height).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.themeSelection(light: AppConfig.store.lightTheme, dark: AppConfig.store.darkTheme).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
