import AppKit
import SwiftUI
import TextierCore

/// A Match Window: the Inspector's view of one entry, popped out, in the Panel's
/// frosted look. Its traffic lights sit in a transparent title bar beside a solid
/// pill naming the Pattern and the entry, the Match's preview and the Action bar;
/// the parsed card fills the rest. Many can be open at once, and each follows
/// config reloads.
@MainActor
final class MatchWindowController: NSObject, NSWindowDelegate {
    /// Open windows, kept alive until they close.
    private(set) static var openControllers: [MatchWindowController] = []
    /// Where the next window's top-left goes, so new windows don't stack exactly.
    private static var cascadePoint = NSPoint.zero

    let window: NSWindow
    let model: MatchWindowModel

    /// Opens a Match Window on an Inspector entry.
    static func open(_ entry: InspectorEntry, patternName: String) {
        let controller = MatchWindowController(model: MatchWindowModel(entry: entry, patternName: patternName))
        openControllers.append(controller)
        controller.show()
    }

    /// Opens a Match Window on text found outside the Inspector (a JSON Viewer
    /// value), parsed like the Inspector would parse it; `actions` are its Match's.
    static func open(text: String, patternName: String, actions: [Action]) {
        open(MatchWindowModel.entry(for: text, actions: actions), patternName: patternName)
    }

    private init(model: MatchWindowModel) {
        self.model = model
        window = KeyEquivalentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        (window as? KeyEquivalentWindow)?.onKeyEquivalent = { [weak self] in self?.goToLine(on: $0) ?? false }
        // The title stays set for the Window menu and VoiceOver; the header shows it.
        window.title = "textier — \(model.patternName)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 360, height: 220)
        window.delegate = self

        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        let lightsWidth = window.standardWindowButton(.zoomButton).map { $0.frame.maxX } ?? 70
        window.contentView = NSVisualEffectView.frosted(around: NSHostingView(rootView: MatchWindowView(
            model: model, titlebarHeight: titlebarHeight, leadingInset: lightsWidth + 12
        )))
        NotificationCenter.default.addObserver(
            self, selector: #selector(configDidReload), name: ConfigStore.didReload, object: nil
        )
    }

    @objc private func configDidReload() {
        model.refresh()
    }

    /// Go to Line's shortcut (⌘G): the Raw editor's bar, switching to Raw first.
    private func goToLine(on event: NSEvent) -> Bool {
        guard let shortcut = Shortcut(event: event), shortcut == AppConfig.current.shortcuts[.goToLine] else { return false }
        if let editor = rawEditor, model.mode == .raw {
            GoToLineBar.show(for: editor)
            return true
        }
        // Switched to Raw, the editor comes with SwiftUI's next update.
        model.mode = .raw
        let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window.contentView?.layoutSubtreeIfNeeded()
                if let editor = self.rawEditor { GoToLineBar.show(for: editor) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    /// The Raw editor's text view, while Raw shows.
    var rawEditor: NSTextView? {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap(find).first
        }
        return window.contentView.flatMap(find)
    }

    private func show() {
        if Self.openControllers.count == 1 { window.center() }
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)
        Effects.present(window)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
        // AppKit may keep a closed window; its content (a JSON Viewer observing
        // config reloads) goes once the close is done.
        RunLoop.main.perform { [window] in
            MainActor.assumeIsolated { window.contentView = nil }
        }
    }
}

/// The entry a Match Window shows, kept current with the Config. Its raw text can
/// be edited, as a scratch copy: the entry is parsed again from the edit, and the
/// Panel's Input never changes.
@MainActor
@Observable
final class MatchWindowModel {
    private(set) var entry: InspectorEntry
    let patternName: String
    /// The Pattern name's Glyph and color, as the Inspector's tab shows them.
    private(set) var glyph: Glyph
    private(set) var color: PatternColor
    var readsAsUTC = false
    /// Parsed or Raw.
    var mode = Mode.parsed

    enum Mode: Hashable { case parsed, raw }

    /// Raw's editor, while Raw shows, for Expand all and Collapse all.
    @ObservationIgnored weak var rawEditor: FoldingTextView?

    /// The Match's text as edited in Raw; parsed again a moment after each edit.
    var rawText: String {
        didSet {
            guard rawText != oldValue else { return }
            scheduleReparse()
        }
    }
    /// Why the edit doesn't parse as the Pattern any more; nil while it does.
    private(set) var problem: String?
    /// The entry as popped out, for View Original; its Actions follow config reloads.
    private var original: InspectorEntry
    /// What Raw opens on: JSON beautified, anything else as it was.
    private let opening: String
    @ObservationIgnored private var reparse: Timer?

    init(entry: InspectorEntry, patternName: String) {
        self.entry = entry
        original = entry
        opening = entry.isJSON ? JSONValue.container(from: entry.text)?.prettyPrinted ?? entry.text : entry.text
        rawText = opening
        self.patternName = patternName
        (glyph, color) = Self.mark(of: patternName)
        // Plain text has nothing to parse, so it opens on its text, ready to edit.
        if !hasParsedView { mode = .raw }
        updateCanBeautify()
    }

    /// Whether the Match has a parsed view beyond its text (JSON, a URL's parts, a
    /// datetime, a file, Fields). Without one there's no Parsed | Raw, only Raw.
    var hasParsedView: Bool {
        if case .text = original.detail { !original.fields.isEmpty } else { true }
    }

    /// The title pill: the Pattern and the entry's number in the Inspector, which
    /// an edit keeps.
    var title: String { "\(patternName) \(original.index)" }

    /// Raw holds something other than the Match, as it was or beautified.
    var isEdited: Bool { rawText != original.text && rawText != opening }

    /// Raw holds the Match's text exactly as it is in the Input.
    var showsOriginal: Bool { rawText == original.text }

    /// The Match Window shows JSON: its raw text is colored.
    var isJSONPattern: Bool { original.isJSON }

    /// JSON not already laid out over lines can be, to edit. Worked out with each
    /// parse of the edit, not on every redraw.
    private(set) var canBeautify = false

    private func updateCanBeautify() {
        guard original.isJSON, let json = JSONValue.container(from: rawText) else {
            canBeautify = false
            return
        }
        canBeautify = json.prettyPrinted != rawText
    }

    func beautify() {
        guard let json = JSONValue.container(from: rawText) else { return }
        rawText = json.prettyPrinted
        canBeautify = false
    }

    /// The Match's text as it is in the Input, undoing Beautify and any edit.
    func viewOriginal() {
        rawText = original.text
        reparse?.invalidate()
        showOriginalEntry()
    }

    /// The entry as popped out, for Raw holding its text or that beautified.
    private func showOriginalEntry() {
        entry = original
        problem = nil
        updateCanBeautify()
    }

    private func scheduleReparse() {
        reparse?.invalidate()
        // A run loop timer, so it also fires while the app tests hold the main queue.
        let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.parseRawText() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reparse = timer
    }

    /// The edit parsed as the Inspector would: the Match of this Pattern spanning
    /// all of it, or else its text, with why it isn't one.
    private func parseRawText() {
        let text = rawText
        guard text != original.text, text != opening else { return showOriginalEntry() }
        var parsed: InspectorEntry
        if let match = Self.wholeMatch(of: text, named: patternName) {
            parsed = Self.entry(for: text, actions: match.actions)
            // An escaped-json window's tree comes from the json Pattern; its Actions
            // stay its own Pattern's.
            parsed.actions = match.actions
            problem = nil
        } else {
            parsed = InspectorEntry(wholeText: text, actions: entry.actions)
            problem = if original.isJSON, let line = JSONValue.errorLine(in: text) {
                "Not valid JSON from line \(line). Shown as text."
            } else {
                "Not a \(patternName) Match any more. Shown as text."
            }
        }
        parsed.index = original.index
        entry = parsed
        updateCanBeautify()
    }

    /// A Pattern name's Glyph and color in the current Config.
    private static func mark(of name: String) -> (Glyph, PatternColor) {
        (AppConfig.current.glyph(ofName: name), AppConfig.current.color(ofName: name))
    }

    var barItems: [ActionBarItem] {
        entry.barItems(isPlainText: false, inMatchWindow: true)
    }

    /// Runs an Action bar button on the entry.
    func run(_ item: ActionBarItem) {
        switch item {
        case .action(let action): action.perform(on: entry, patternName: patternName)
        case .copyWithLine: entry.pathWithLine.map(copyToPasteboard)
        case .popOut: break  // never offered in a Match Window
        }
    }

    /// After a reload: the Pattern's Actions may have changed. The entry's text is
    /// detected again, and the Match spanning all of it, from a Pattern of the same
    /// name, gives the Actions; Patterns that share a name keep their own, and a
    /// reorder doesn't mix them up. The JSON Viewer and the colors follow the reload
    /// by themselves.
    func refresh() {
        if let match = Self.wholeMatch(of: entry.text, named: patternName) {
            entry.actions = match.actions
        }
        // So View Original (or typing back to the original) doesn't bring back old Actions.
        if let match = Self.wholeMatch(of: original.text, named: patternName) {
            original.actions = match.actions
        }
        (glyph, color) = Self.mark(of: patternName)
    }

    /// `text` inspected on its own: the entry of the Match that spans all of it, or
    /// a text entry with `actions`.
    static func entry(for text: String, actions: [Action]) -> InspectorEntry {
        let inspection = inspect(
            text, config: AppConfig.current, now: Date(), timeZone: .current,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
        let whole = NSRange(text.startIndex..., in: text)
        if let entry = inspection.tabs.lazy.flatMap(\.entries).first(where: { $0.range == whole && $0.parent == nil }) {
            return entry
        }
        return InspectorEntry(wholeText: text, actions: actions)
    }

    /// The top-level Match spanning all of `text` when a Pattern named `name` finds it.
    /// `escaped-json` finds nothing in text (it applies in the JSON Viewer), so a
    /// window popped out of an escaped JSON string has a Match while its text is
    /// still JSON, with that Pattern's Actions.
    private static func wholeMatch(of text: String, named name: String) -> Match? {
        let config = AppConfig.current
        let whole = NSRange(text.startIndex..., in: text)
        if let pattern = config.escapedJSONPattern, pattern.name == name {
            guard JSONValue.container(from: text) != nil, let index = config.patterns.firstIndex(of: pattern) else {
                return nil
            }
            return Match(range: whole, text: text, patternName: name, patternIndex: index, actions: pattern.actions)
        }
        return detect(text, config: config).first { $0.range == whole && $0.patternName == name }
    }
}

private struct MatchWindowView: View {
    @Bindable var model: MatchWindowModel
    /// The transparent title bar's height, which the title pill and preview share
    /// with the traffic lights.
    let titlebarHeight: CGFloat
    /// Where the title bar's content starts, past the traffic lights.
    let leadingInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TitlePill(glyph: model.glyph, title: model.title, color: model.color)
                Text(model.entry.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)
                ActionBar(items: model.barItems, color: model.color) { model.run($0) }
                    .fixedSize()
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, 10)
            .frame(height: titlebarHeight)
            .padding(.bottom, 4)
            RawBar(model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Group {
                switch model.mode {
                case .parsed:
                    // JSON's Tree | Raw is the window's own switch, so the viewer shows none.
                    EntryDetailView(
                        entry: model.entry, readsAsUTC: $model.readsAsUTC, accent: model.color,
                        showsJSONModePicker: !model.isJSONPattern
                    )
                case .raw:
                    RawEditor(text: $model.rawText, colorsJSON: model.isJSONPattern) { [model] in model.rawEditor = $0 }
                        .card()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Parsed or Raw, and the state of an edit: what's wrong with it, Beautify for
/// JSON, and View Original, back to the text as it is in the Input.
private struct RawBar: View {
    @Bindable var model: MatchWindowModel

    var body: some View {
        HStack(spacing: 10) {
            if model.hasParsedView {
                Picker("View", selection: $model.mode) {
                    // As the JSON Viewer names its views; Raw is editable here.
                    Text(model.isJSONPattern ? "Tree" : "Parsed").tag(MatchWindowModel.Mode.parsed)
                    Text("Raw").tag(MatchWindowModel.Mode.raw)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if model.isEdited {
                Text("Edited here only; the Input keeps the original")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if model.mode == .raw, model.isJSONPattern {
                IconButton(title: "Expand all", systemImage: "rectangle.expand.vertical") {
                    model.rawEditor?.folding?.unfoldAll()
                }
                IconButton(title: "Collapse all", systemImage: "rectangle.compress.vertical") {
                    model.rawEditor?.folding?.foldAll()
                }
            }
            if model.mode == .raw, model.canBeautify {
                Button("Beautify") { model.beautify() }
                    .controlSize(.small)
            }
            if !model.showsOriginal {
                Button("View Original") { model.viewOriginal() }
                    .controlSize(.small)
                    .help("Show the text as it is in the Input, undoing Beautify and any edit")
            }
        }
    }
}

/// The Match's text, editable, in a monospaced face; JSON syntax-colored as Text
/// mode colors it, again after each edit, and folding (`FoldingTextView`).
private struct RawEditor: NSViewRepresentable {
    @Binding var text: String
    let colorsJSON: Bool
    /// Given the text view once it's made.
    var onTextView: (FoldingTextView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, colorsJSON: colorsJSON) }

    func makeNSView(context: Context) -> NSScrollView {
        // Set up as `NSTextView.scrollableTextView()` sets one up, but a text view
        // whose ⌘C is textier's own copy, and TextKit 1, which the line numbers and
        // folding use.
        let textView = FoldingTextView.make(foldsJSON: colorsJSON)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = JSONColoring.font
        // The line numbers keep the text off the edge.
        textView.textContainerInset = NSSize(width: 2, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.string = text
        textView.delegate = context.coordinator
        // ⌘F finds in the text, as in any text view.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        let ruler = LineNumberRuler(textView: textView)
        ruler.showsGutter = true
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.recolor(textView)
        onTextView(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        // Only an outside change (Beautify, View Original) replaces the text, keeping the
        // cursor and undo while typing. It goes through the text system as one undo
        // step: ⌘Z takes it back, and the typing before it then undoes against the
        // text it was typed into (setting `string` leaves those steps pointing into
        // text that's gone).
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: whole, replacementString: text) else {
            textView.string = text
            textView.undoManager?.removeAllActions()
            return context.coordinator.recolor(textView)
        }
        // didChangeText recolors, through the delegate.
        context.coordinator.isApplyingOutsideChange = true
        textView.textStorage?.replaceCharacters(
            in: whole, with: NSAttributedString(string: text, attributes: textView.typingAttributes)
        )
        textView.didChangeText()
        context.coordinator.isApplyingOutsideChange = false
        textView.breakUndoCoalescing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let colorsJSON: Bool
        /// Set while `updateNSView` puts the model's text in, which needn't go back.
        var isApplyingOutsideChange = false

        init(text: Binding<String>, colorsJSON: Bool) {
            self.text = text
            self.colorsJSON = colorsJSON
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            recolor(textView)
            guard !isApplyingOutsideChange else { return }
            text.wrappedValue = textView.string
        }

        /// The themes' token colors over the text, as far as it's JSON; the rest in
        /// the themes' foreground. Attributes only, so undo and the cursor stay put.
        @MainActor
        func recolor(_ textView: NSTextView) {
            guard colorsJSON, let storage = textView.textStorage else { return }
            storage.beginEditing()
            storage.addAttribute(
                .foregroundColor, value: NSColor.themeForeground, range: NSRange(location: 0, length: storage.length)
            )
            for token in colorize(storage.string, theme: AppConfig.store.lightTheme) {
                storage.addAttribute(.foregroundColor, value: JSONColoring.color(for: token.kind), range: token.range)
            }
            storage.endEditing()
            textView.typingAttributes[.foregroundColor] = NSColor.themeForeground
        }
    }
}

/// The Match Window's title: the Pattern's Glyph, name and the entry's index on a
/// solid pill in its color.
private struct TitlePill: View {
    let glyph: Glyph
    let title: String
    let color: PatternColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(color, \.onSolid))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(color, \.solid)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A window that offers its key equivalents to a handler before the usual route.
final class KeyEquivalentWindow: NSWindow {
    var onKeyEquivalent: (NSEvent) -> Bool = { _ in false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyEquivalent(event) || super.performKeyEquivalent(with: event)
    }
}
