import AppKit
import SwiftUI
import TextierCore

/// An entry parsed, in a card: JSON in the JSON Viewer, a URL in parts, a datetime
/// converted, a file path located, anything else as its text, with the entry's
/// Fields above. The Inspector and Match Windows both show it.
struct EntryDetailView: View {
    let entry: InspectorEntry
    @Binding var readsAsUTC: Bool
    /// The Pattern's color, which the JSON Viewer marks its search matches in.
    var accent: PatternColor = Palette.fallback
    /// Whether the JSON Viewer shows its own Tree | Raw switch.
    var showsJSONModePicker = true
    /// What the JSON Viewer opens on: the tree, or the beautified text (the
    /// Selection Popover's quick look).
    var jsonMode = JSONDetailView.Mode.tree

    var body: some View {
        if case .json(let value) = entry.detail {
            // A new value (an edit, another entry) gets a fresh JSON Viewer.
            JSONDetailView(
                value: value, source: entry.text, accent: accent, showsModePicker: showsJSONModePicker, mode: jsonMode
            )
                .id(entry.text)
                .card()
        } else {
            parsed.card()
        }
    }

    /// The most of a Match's text its Fields card shows.
    private static let fieldsTextShown = 10_000

    @ViewBuilder private var parsed: some View {
        switch entry.detail {
        case .json:
            EmptyView()
        case .url(let url):
            DetailRows { fieldRows; urlRows(url) }
        case .datetime(let datetime):
            DetailRows { fieldRows; datetimeRows(datetime) }
        case .filePath(let file):
            DetailRows { fieldRows; fileRows(file) }
        case .text(let text) where !entry.fields.isEmpty:
            // A Match with Fields is mostly a line or two, scrolling with its Fields;
            // past `fieldsTextShown` characters the rest is left to Copy and Pop Out,
            // as the text is laid out whole.
            DetailRows {
                fieldRows
                FieldsTextHost(text: text.prefix(Self.fieldsTextShown + 1).count > Self.fieldsTextShown
                               ? text.prefix(Self.fieldsTextShown) + "…" : text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        case .text(let text):
            PlainTextHost(text: text)
        }
    }

    /// The Fields, a row each, before the parsed view.
    @ViewBuilder private var fieldRows: some View {
        if !entry.fields.isEmpty {
            ForEach(Array(entry.fields.enumerated()), id: \.offset) { _, field in
                HStack(spacing: 6) {
                    CopyRow(label: field.field.label, value: field.field.value, copy: field.copy)
                    if let link = field.link {
                        ForEach(field.linkActions, id: \.self) { action in
                            Button(action.title) { action.perform(on: link) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .padding(.trailing, 10)
                        }
                    }
                }
            }
        }
    }

    /// The whole URL, then its parts, then its query parameters in a section of
    /// their own, named in code type like their values.
    @ViewBuilder private func urlRows(_ url: URLDetail) -> some View {
        CopyRow(label: "URL", value: entry.text)
        CopyRow(label: "Scheme", value: url.scheme)
        CopyRow(label: "Host", value: url.host)
        if let port = url.port { CopyRow(label: "Port", value: String(port)) }
        CopyRow(label: "Path", value: url.path.isEmpty ? "/" : url.path)
        if let fragment = url.fragment { CopyRow(label: "Fragment", value: fragment) }
        if !url.query.isEmpty {
            SectionLabel("Query", detail: counted(url.query.count, "parameter"))
            ForEach(Array(url.query.enumerated()), id: \.offset) { _, parameter in
                CopyRow(label: parameter.name, value: parameter.value, codeLabel: true)
            }
        }
    }

    @ViewBuilder private func datetimeRows(_ datetime: DatetimeDetail) -> some View {
        let conversions = readsAsUTC ? datetime.asUTC ?? datetime.conversions : datetime.conversions
        if datetime.asUTC != nil {
            HStack {
                Text(readsAsUTC ? "No offset: read as UTC" : "No offset: assumed local")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer()
                Toggle("Read as UTC", isOn: $readsAsUTC)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        CopyRow(label: "ISO 8601 UTC", value: conversions.isoUTC)
        CopyRow(label: "Local", value: conversions.local)
        CopyRow(label: "Epoch seconds", value: conversions.epochSeconds)
        CopyRow(label: "Epoch ms", value: conversions.epochMilliseconds)
        CopyRow(label: "Relative", value: conversions.relative)
    }

    @ViewBuilder private func fileRows(_ file: FilePathDetail) -> some View {
        CopyRow(label: "Path", value: file.path)
        if let line = file.line {
            CopyRow(label: "Line", value: String(line), note: file.lineSource == .lineKey ? "(from `line`)" : nil)
        }
        if let column = file.column { CopyRow(label: "Column", value: String(column)) }
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("On this Mac")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 0)
            Chip(text: file.exists ? "exists" : "not found", color: file.exists ? Palette.success : Palette.failure)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// Rows of label/value pairs, top-aligned and scrollable, with a faint line between
/// each two.
private struct DetailRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                        if position > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                        }
                        row
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)
        }
        .mask(EdgeFade(top: 6, bottom: 12))
    }
}

extension View {
    /// A parsed view's card: rounded 10 pt to nest in the Inspector pane, a shade
    /// lighter than it.
    func card() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 10))
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: NSColor(
                light: NSColor.white.withAlphaComponent(0.72), dark: NSColor.white.withAlphaComponent(0.05)
            ))))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

/// A section's heading on a faint band across the card: a small caps title and
/// what's in it ("2 parameters").
private struct SectionLabel: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let detail {
                Text("· \(detail)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .padding(.top, 6)
    }
}

/// A label and a value that copies on click, with an optional note after the
/// value that isn't copied.
private struct CopyRow: View {
    let label: String
    let value: String
    var note: String?
    /// The label is a name from the value's world (a query parameter), set like code.
    var codeLabel = false
    /// What a click does; copies `value` unless given.
    var copy: (() -> Void)?
    @State private var hovering = false
    /// Just copied: the copy icon is a checkmark for a moment.
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if let copy { copy() } else { copyToPasteboard(value) }
            copied = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(codeLabel ? .system(size: 12, design: .monospaced) : .system(size: 11.5))
                    .foregroundStyle(codeLabel ? AnyShapeStyle(Color(nsColor: JSONColoring.color(for: .key))) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 110, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 12, design: .monospaced))
                        .multilineTextAlignment(.leading)
                    if let note {
                        Text(LocalizedStringKey(note))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .font(.system(size: 11, weight: copied ? .semibold : .regular))
                    .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onChange(of: copied) {
            guard copied else { return }
            // A run loop timer, as the app's other delays (docs/agents/testing.md).
            let timer = Timer(timeInterval: 1.2, repeats: false) { _ in
                MainActor.assumeIsolated { copied = false }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        .help("Click to copy")
    }
}

// MARK: JSON

/// The JSON Viewer for a JSON entry, after mockup "JSON Viewer Redesign": Tree or
/// Raw, a search field, Expand all and Collapse all; in Tree, a path bar naming
/// the selected row's place with its actions; and a footer with the JSON's size
/// and the search's matches.
struct JSONDetailView: View {
    let value: JSONValue
    /// Without the Tree | Raw switch, where the window has its own (a Match Window).
    var showsModePicker = true
    @State private var mode = Mode.tree
    @State private var tree: JSONTreeModel
    /// The Raw text's search matches.
    @State private var rawMatches = 0

    enum Mode: Hashable {
        case tree, raw
    }

    /// `mode` is the one it opens on; the switch changes it from there.
    init(value: JSONValue, source: String, accent: PatternColor, showsModePicker: Bool = true, mode: Mode = .tree) {
        self.value = value
        self.showsModePicker = showsModePicker
        _mode = State(initialValue: mode)
        _tree = State(initialValue: JSONTreeModel(value: value, source: source, accent: accent))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if showsModePicker {
                    Picker("View", selection: $mode) {
                        Text("Tree").tag(Mode.tree)
                        Text("Raw").tag(Mode.raw)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                JSONSearchField(text: $tree.query, prompt: mode == .tree ? "Filter, or a $.path query" : "Find in text")
                    .frame(minWidth: 120, maxWidth: 300)
                    .help("Text finds keys and values; a JSONPath query (starting with $) finds what it selects: "
                        + "$.backtrace[*].file, $..line, $.backtrace[?@.line > 100]")
                if mode == .tree, tree.isPathQuery, tree.matchCount > 0 {
                    Button("Copy Results") { tree.viewer.copyResults() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .help("Copy what the query found, as a JSON array")
                }
                Spacer(minLength: 0)
                switch mode {
                case .tree:
                    // Closures, not method references: Xcode 26.6's compiler (CI) has
                    // crashed on those.
                    ExpandCollapseButtons(expand: { tree.viewer.expandAll() }, collapse: { tree.viewer.collapseAll() })
                case .raw:
                    ExpandCollapseButtons(
                        expand: { tree.rawTextView?.folding?.unfoldAll() }, collapse: { tree.rawTextView?.folding?.foldAll() }
                    )
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            switch mode {
            case .tree:
                PathBar(tree: tree)
                JSONTreeHost(viewer: tree.viewer)
                    .overlay {
                        if tree.isSearching, tree.matchCount == 0 {
                            Text("Nothing matches “\(tree.query.trimmingCharacters(in: .whitespaces))”")
                                .foregroundStyle(.secondary)
                        }
                    }
            case .raw:
                JSONTextHost(
                    text: tree.pretty, light: AppConfig.store.lightTheme, dark: AppConfig.store.darkTheme,
                    query: tree.appliedQuery, accent: tree.accent, onTextView: { [tree] in tree.rawTextView = $0 }
                ) { rawMatches = $0 }
            }
            JSONFooter(
                stats: tree.stats,
                matches: tree.query.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                    : mode == .tree ? tree.matchCount : rawMatches,
                problem: mode == .tree ? tree.searchError : nil,
                accent: tree.accent
            )
        }
    }
}

/// The JSON Viewer behind a JSON entry: the node selected in it, and its search,
/// run a moment after typing stops.
@MainActor
@Observable
final class JSONTreeModel {
    @ObservationIgnored let viewer: JSONViewer
    let accent: PatternColor
    private(set) var selected: JSONNode?
    /// Bumped when a node expands or collapses, so the path bar's labels follow.
    private(set) var revision = 0
    var query = "" {
        didSet { scheduleSearch() }
    }
    private(set) var matchCount = 0
    private(set) var isSearching = false
    private(set) var isPathQuery = false
    private(set) var searchError: String?
    @ObservationIgnored private var searchTimer: Timer?

    /// The search as last run, a moment after typing stopped.
    private(set) var appliedQuery = ""
    @ObservationIgnored private let source: String

    /// Raw's text view, while Raw shows, for Expand all and Collapse all.
    @ObservationIgnored weak var rawTextView: FoldingTextView?

    /// The JSON beautified, for Raw; made once, when first shown.
    @ObservationIgnored private(set) lazy var pretty = viewer.root.value.prettyPrinted

    /// The footer's "8 keys · 1.2 KB · 36 lines"; worked out once.
    @ObservationIgnored private(set) lazy var stats: String = {
        let bytes = source.utf8.count
        let size = bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
        let lines = pretty.utf8.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        return [viewer.root.value.openSummary, size, "\(lines) lines"].filter { !$0.isEmpty }.joined(separator: " · ")
    }()

    init(value: JSONValue, source: String, accent: PatternColor) {
        viewer = JSONViewer(value: value)
        self.source = source
        self.accent = accent
        viewer.accent = accent
        viewer.onSelectionChange = { [weak self] in self?.selected = $0 }
        viewer.onExpansionChange = { [weak self] in self?.revision += 1 }
        viewer.onSearchChange = { [weak self] in
            guard let self else { return }
            matchCount = viewer.matchCount
            isSearching = viewer.isSearching
            isPathQuery = viewer.isPathQuery
            searchError = viewer.searchError
            revision += 1
        }
    }

    private func scheduleSearch() {
        searchTimer?.invalidate()
        // A run loop timer, so it also fires while the app tests hold the main queue.
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.appliedQuery = self.query
                self.viewer.search(self.query)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        searchTimer = timer
    }
}

/// The selected row's place as a path (`$` › `backtrace` › `[0]` › `file`, each a
/// button that selects it), what it is, and its actions: a link value's Actions
/// (Copy with Line on a paired `file` value), an escaped-JSON string's parse
/// toggle and `open`, Copy Value and Copy Path.
private struct PathBar: View {
    let tree: JSONTreeModel

    var body: some View {
        let _ = tree.revision
        HStack(spacing: 8) {
            if let node = tree.selected {
                let viewer = tree.viewer
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        let chain = node.pathSteps
                        ForEach(Array(chain.enumerated()), id: \.offset) { index, step in
                            Text(step.separator).foregroundStyle(.tertiary)
                            Button(step.label) { viewer.select(step.node) }
                                .buttonStyle(.plain)
                                .foregroundStyle(index == chain.count - 1 ? Color(tree.accent, \.text) : .secondary)
                                .fontWeight(index == chain.count - 1 ? .semibold : .regular)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
                .frame(minWidth: 60)
                Text(Self.description(of: node.content(parsedInline: viewer.isParsedInline(node))))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                actions(of: node, in: viewer)
            } else {
                Text("Select a row to see its path")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .frame(height: 30)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder private func actions(of node: JSONNode, in viewer: JSONViewer) -> some View {
        HStack(spacing: 4) {
            if let match = node.stringMatch {
                // Its Copy is Copy Value's.
                ForEach(match.actions.filter { $0 != .copy }, id: \.self) { action in
                    Button(action.title) { action.perform(on: match, pairedLine: node.pairedLine) }
                }
                if node.pairedLine != nil {
                    Button(ActionBarItem.copyWithLine.title) { viewer.copyWithLine(of: node) }
                }
            }
            if node.escapedJSON != nil {
                Button(viewer.isParsedInline(node) ? "Show as String" : "Parse Inline") {
                    viewer.toggleInline(node)
                }
                let config = AppConfig.current
                if let pattern = config.escapedJSONPattern, let index = config.patterns.firstIndex(of: pattern),
                   case .string(let string) = node.value {
                    ForEach(pattern.actions, id: \.self) { action in
                        Button(action.title) {
                            action.perform(on: Match(
                                range: NSRange(string.startIndex..., in: string), text: string,
                                patternName: pattern.name, patternIndex: index, actions: pattern.actions
                            ))
                        }
                    }
                }
            }
            Button("Copy Value") { viewer.copyValue(of: node) }
            if node.component != nil {
                Button("Copy Path") { copyToPasteboard(node.keyPathString) }
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize()
    }

    /// "string · 98 chars", "object · 3 keys", "number"…
    static func description(of value: JSONValue) -> String {
        switch value {
        case .string(let string): "string · \(counted(string.count, "char"))"
        case .object: "object · \(value.openSummary)"
        case .array: "array · \(value.openSummary)"
        case .number: "number"
        case .bool: "boolean"
        case .null: "null"
        }
    }
}

/// The JSON's size, and the search's match count in the Pattern's color, or why a
/// query can't be read.
private struct JSONFooter: View {
    let stats: String
    let matches: Int?
    let problem: String?
    let accent: PatternColor

    var body: some View {
        HStack {
            Text(stats)
            Spacer(minLength: 8)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let matches {
                Text(counted(matches, "match"))
                    .foregroundStyle(Color(accent, \.text))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color.primary.opacity(0.035))
    }
}

/// Expand all and Collapse all, for a Tree's rows or Raw's folds.
struct ExpandCollapseButtons: View {
    let expand: () -> Void
    let collapse: () -> Void

    var body: some View {
        IconButton(title: "Expand all", systemImage: "rectangle.expand.vertical", action: expand)
        IconButton(title: "Collapse all", systemImage: "rectangle.compress.vertical", action: collapse)
    }
}

/// An icon button with a hover fill, for the JSON Viewer's toolbar and the Match
/// Window's Raw bar.
private struct IconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A native search field: Esc clears it (and only an empty one lets Esc through,
/// to close the Panel), and ⌘F in its window puts the cursor in it.
struct JSONSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.controlSize = .small
        field.sendsWholeSearchString = false
        context.coordinator.field = field
        context.coordinator.watchForFind()
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.placeholderString != prompt { field.placeholderString = prompt }
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        weak var field: NSSearchField?
        private var monitor: Any?

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field else { return }
            text.wrappedValue = field.stringValue
        }

        /// Esc clears a field with text in it, and goes no further.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), let field, !field.stringValue.isEmpty else {
                return false
            }
            field.stringValue = ""
            text.wrappedValue = ""
            return true
        }

        func watchForFind() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Local monitors run on the main thread.
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated { self?.focusIfFind(event) == true }
                return handled ? nil : event
            }
        }

        func stopWatching() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// ⌘F in this field's window: the cursor goes to the field.
        func focusIfFind(_ event: NSEvent) -> Bool {
            guard let field, let window = field.window, event.window === window,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "f"
            else { return false }
            window.makeFirstResponder(field)
            return true
        }
    }
}

/// Embeds a JSON Viewer's outline.
private struct JSONTreeHost: NSViewRepresentable {
    let viewer: JSONViewer

    func makeNSView(context: Context) -> NSScrollView { viewer.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// The beautified JSON, read-only, syntax-colored with the theme for the current
/// appearance, with line numbers. It's text: URLs and paths are strings like any
/// other (the tree's rows are where they open). What the search finds is marked in
/// the Pattern's color, and the first one scrolled to. Its objects and arrays fold
/// (`FoldingTextView`); what the search finds is expanded.
private struct JSONTextHost: NSViewRepresentable {
    let text: String
    let light: Theme
    let dark: Theme
    var query = ""
    var accent: PatternColor = Palette.fallback
    /// Given the text view once it's made.
    var onTextView: (FoldingTextView) -> Void = { _ in }
    /// Called with how many times the search is found.
    var onMatches: (Int) -> Void = { _ in }

    func makeCoordinator() -> JSONTextCoordinator { JSONTextCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // The line numbers keep the text off the edge.
        let (scrollView, textView) = readOnlyTextView(inset: NSSize(width: 2, height: 8), foldsJSON: true)
        textView.isRichText = true
        textView.delegate = context.coordinator
        let ruler = LineNumberRuler(textView: textView)
        ruler.showsGutter = true
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.show(text, light: light, dark: dark)
        context.coordinator.mark(query, in: accent, onMatches: onMatches)
        onTextView(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.show(text, light: light, dark: dark)
        context.coordinator.mark(query, in: accent, onMatches: onMatches)
    }
}

@MainActor
private final class JSONTextCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: NSTextView?
    /// What's shown.
    private var shown: (text: String, light: Theme, dark: Theme)?

    func show(_ text: String, light: Theme, dark: Theme) {
        if let shown, shown.text == text, shown.light == light, shown.dark == dark { return }
        // The same text in other colors keeps its folds.
        let kept = shown?.text == text ? folding?.folded ?? [] : []
        shown = (text, light, dark)
        textView?.textStorage?.setAttributedString(JSONColoring.attributedString(text, light: light, dark: dark))
        folding?.refold(kept)
        textView?.drawsBackground = false
        textView?.selectedTextAttributes = [.backgroundColor: NSColor.themeSelection(light: light, dark: dark)]
    }

    /// The search last marked.
    private var marked: String?
    /// The ranges the search last found.
    private(set) var found: [NSRange] = []

    /// Marks every place `query` is found, ignoring case, scrolls to the first and
    /// reports the count (on the next run loop turn, outside SwiftUI's update).
    func mark(_ query: String, in accent: PatternColor, onMatches: @escaping (Int) -> Void) {
        self.onMatches = onMatches
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query != marked, let textView, let layoutManager = textView.layoutManager else { return }
        marked = query
        let text = textView.string as NSString
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
        found = []
        if !query.isEmpty {
            var search = NSRange(location: 0, length: text.length)
            while true {
                let range = text.range(of: query, options: .caseInsensitive, range: search)
                guard range.location != NSNotFound else { break }
                found.append(range)
                search = NSRange(location: NSMaxRange(range), length: text.length - NSMaxRange(range))
            }
            folding?.unfold(revealing: found)
            let color = NSColor.pattern(accent, \.strongTint)
            for range in found {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
            if let first = found.first { textView.scrollRangeToVisible(first) }
        }
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onMatches(self.found.count)
            }
        }
    }

    private var onMatches: (Int) -> Void = { _ in }

    private var folding: FoldingLayoutManager? { textView?.layoutManager as? FoldingLayoutManager }
}

/// A read-only, selectable text view that wraps at its width, in a scroll view of
/// its own, both clear on the card. TextKit 1, which the line number ruler,
/// non-contiguous layout and folding need; JSON folds with `foldsJSON`.
@MainActor
private func readOnlyTextView(inset: NSSize, foldsJSON: Bool = false) -> (NSScrollView, FoldingTextView) {
    let textView = FoldingTextView.make(foldsJSON: foldsJSON)
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = inset
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true

    let scrollView = TextCardScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.documentView = textView
    return (scrollView, textView)
}

/// The scroll view of a card's text. TextKit draws the text in a content layer of
/// its own, and a card opening (the Selection Popover's, on JSON Raw) resizes the
/// text view and its clip view after that layer first drew: the text showed lines
/// too low until scrolled. Only a scroll that a frame draws at has the layer draw
/// again, so on each resize the clip view moves a point, and back a moment later;
/// and once more when the resizing has settled, as the card's animation ends.
private final class TextCardScrollView: NSScrollView {
    /// The text view's width and the clip view's size the layer last drew at. Not
    /// the text view's height: that changes alone as Raw JSON folds, which the
    /// nudge would make bounce.
    private var sizes: [NSSize] = []
    private var isNudging = false
    private var settleTimer: Timer?

    override func tile() {
        super.tile()
        let sizes = [NSSize(width: documentView?.frame.width ?? 0, height: 0), contentView.frame.size]
        guard sizes != self.sizes else { return }
        self.sizes = sizes
        nudge()
        settleTimer?.invalidate()
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.nudge() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func nudge() {
        guard !isNudging else { return }
        isNudging = true
        // Only up and down: the line number ruler sets the sideways offset.
        let y = contentView.bounds.minY
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: y + 1))
        // Back after a frame has drawn there.
        let back = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.contentView.scroll(to: NSPoint(x: self.contentView.bounds.minX, y: y))
                self.reflectScrolledClipView(self.contentView)
                self.isNudging = false
            }
        }
        RunLoop.main.add(back, forMode: .common)
    }
}

/// An entry's text, read-only and selectable: a Plain Text piece can be most of a
/// large Input, which SwiftUI's Text would lay out whole, and again on every width
/// change. This lays out only as far as it's scrolled.
private struct PlainTextHost: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> PlainTextCoordinator { PlainTextCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // The line fragment's own padding makes up the 14 pt the other cards' rows have.
        let (scrollView, textView) = readOnlyTextView(inset: NSSize(width: 9, height: 12))
        textView.layoutManager?.allowsNonContiguousLayout = true
        context.coordinator.textView = textView
        context.coordinator.show(text)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.show(text)
    }
}

/// A Match's text under its Fields: read-only and selectable, without a scroll view
/// of its own (it scrolls with the rows), as tall as its text wrapped at the width
/// it's offered. A text view rather than SwiftUI's Text, so a ⌘C in it is
/// textier's own copy.
private struct FieldsTextHost: NSViewRepresentable {
    let text: String

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        .foregroundColor: NSColor.labelColor,
    ]

    func makeNSView(context: Context) -> NSTextView {
        let textView = OwnCopyTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        // The rows' padding places it, as it placed the Text this replaces.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        // SwiftUI sets the frame; the container follows its width, and holds all the
        // text's height.
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        show(text, in: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        show(text, in: textView)
    }

    private func show(_ text: String, in textView: NSTextView) {
        guard textView.string != text else { return }
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
    }

    /// The text's height wrapped at the offered width; its widest line when no width
    /// is offered.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        // Measured in the view's own container, put back after: the width offered
        // may not be the one SwiftUI settles on.
        let size = container.size
        container.size = NSSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = layoutManager.usedRect(for: container).height
        // The used rect spans the container's width; the glyphs, the widest line.
        let widest = width == nil
            ? layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(for: container), in: container).width : 0
        container.size = size
        return CGSize(width: width ?? ceil(widest), height: ceil(height))
    }
}

@MainActor
private final class PlainTextCoordinator {
    weak var textView: NSTextView?
    private var shown: String?

    private static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }()

    func show(_ text: String) {
        guard text != shown else { return }
        shown = text
        textView?.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
    }
}

/// Builds syntax-colored JSON text from the light and dark themes.
@MainActor
enum JSONColoring {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// `text` colored token by token, each color following the appearance.
    static func attributedString(_ text: String, light: Theme, dark: Theme) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(lightHex: light.foreground, darkHex: dark.foreground),
        ])
        let lightRanges = colorize(text, theme: light)
        let darkRanges = colorize(text, theme: dark)
        for (lightRange, darkRange) in zip(lightRanges, darkRanges) where lightRange.range == darkRange.range {
            string.addAttributes([
                .foregroundColor: NSColor(lightHex: lightRange.style.color, darkHex: darkRange.style.color),
                .font: font(lightRange.style.fontStyle),
            ], range: lightRange.range)
            if lightRange.style.fontStyle.contains(.underline) {
                string.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: lightRange.range)
            }
        }
        return string
    }

    static func font(_ style: FontStyle) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.contains(.bold) { traits.insert(.bold) }
        if style.contains(.italic) { traits.insert(.italic) }
        guard !traits.isEmpty else { return font }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }

    /// The style color for a token kind in the current appearance.
    static func color(for kind: JSONTokenKind) -> NSColor {
        NSColor(
            lightHex: AppConfig.store.lightTheme.style(for: kind).color,
            darkHex: AppConfig.store.darkTheme.style(for: kind).color
        )
    }
}
