import AppKit
import SwiftUI
import TextierCore

/// Owns the Panel: a borderless, frosted, floating, centered, resizable window with
/// the editable Input on the left and the Inspector on the right.
///
/// The window's content is SwiftUI (the header, the Inspector); the Input is the
/// AppKit text view, embedded in a split view whose divider is invisible and whose
/// position is remembered. The Inspector is hidden while the Input has no Matches.
@MainActor
final class PanelController: NSObject, NSTextViewDelegate, NSSplitViewDelegate {
    let model = PanelModel()
    // Internal rather than private so the app tests can drive them.
    let textView = InputTextView.make()
    private lazy var inputScrollView = makeInputScrollView()
    private(set) lazy var inspectorView = NSHostingView(rootView: InspectorView(model: model))
    private(set) lazy var splitView = makeSplitView()
    private(set) lazy var panel = makePanel()
    /// The pending re-inspection after an edit: a run loop timer, so it also fires
    /// while the app tests hold the main queue.
    private var inspection: Timer?
    /// Set when an edit replaced the whole Input, so the next pass orders tabs afresh.
    private var replacedWholeInput = false
    /// Set while the split view is laid out from code, so only the user's drags are remembered.
    private var isPlacingDivider = false
    /// Follows the first responder, so the rows know when the list has focus.
    private var focusObservation: NSKeyValueObservation?

    static let inspectorWidthKey = "inspectorWidth"
    private static let defaultSize = NSSize(width: 1100, height: 650)

    func show() {
        panel.center()
        Effects.present(panel)
        // SwiftUI mounts the split view (and so the Input) on its first layout pass.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeFirstResponder(textView)
    }

    /// Replaces the Input with `input`, inspects it at once, turns Highlighting on
    /// and shows the Panel.
    func show(input: String) {
        inspection?.invalidate()
        replacedWholeInput = false
        _ = panel
        textView.string = input
        // The old undo stack describes text that is gone.
        textView.undoManager?.removeAllActions()
        model.highlighting = true
        textView.fadesNewPills = false
        model.inspect(input, fresh: true)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        updateWarnings()
        show()
    }

    /// Re-inspects the Input with the reloaded Config and refreshes the warnings.
    func configDidChange() {
        inspection?.invalidate()
        textView.fadesNewPills = false
        model.inspect(textView.string, fresh: false)
        updateWarnings()
    }

    // MARK: Input

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            // NSTextView would otherwise treat Esc as a request for completions. The
            // window decides: it hides, or leaves full screen.
            panel.cancelOperation(nil)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            guard model.inspection.showsInspector else { return false }
            model.focusList()
            return true
        default:
            return false
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        if range.location == 0, range.length == (textView.string as NSString).length { replacedWholeInput = true }
        return true
    }

    func textDidChange(_ notification: Notification) {
        model.inputDidChange()
        inspection?.invalidate()
        inspection = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // What typing brings in fades in; a paste over everything shows at once.
                // A large Input's pills come later, so `inspectionDidChange` resets it.
                self.textView.fadesNewPills = !self.replacedWholeInput
                self.model.inspect(self.textView.string, fresh: self.replacedWholeInput)
                self.replacedWholeInput = false
            }
        }
    }

    private func makeInputScrollView() -> NSScrollView {
        textView.delegate = self
        textView.onClick = { [weak self] match in self?.open(match) }
        textView.onDoubleClick = { [weak self] match in self?.copy(match) }

        let scrollView = FadingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRuler(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        textView.wrapsLines = model.wrapsLines
        return scrollView
    }

    /// A click on a Match: selects it in the Inspector, leaving the cursor where the
    /// click put it rather than selecting the Match's text, so a click still edits there.
    private func open(_ match: Match) {
        let cursor = textView.selectedRange()
        model.select(match)
        textView.setSelectedRange(cursor)
    }

    /// A double-click on a Match copies it: JSON raw or beautified per `copyJSON`,
    /// anything else raw.
    private func copy(_ match: Match) {
        if AppConfig.current.copyJSON == .pretty, AppConfig.current.pattern(of: match)?.kind == .builtin(.json),
           let json = JSONValue.container(from: match.text) {
            copyToPasteboard(json.prettyPrinted)
        } else {
            copyToPasteboard(match.text)
        }
    }

    // MARK: Inspector

    private func inspectionDidChange(_ inspection: Inspection) {
        textView.matches = inspection.matches
        textView.fadesNewPills = false
        showSelectionInInput()
        setInspectorShown(inspection.showsInspector)
    }

    /// Rings the Inspector's selected entry in the Input; Plain Text isn't a Match.
    private func showSelectionInInput() {
        // The entry's own color, a Color Rule's when one applies.
        textView.inspected = model.selectedMatch.map { ($0.entry.range, $0.color) }
    }

    /// The table behind the Inspector's SwiftUI list of entries (not a JSON Viewer's outline).
    var entryList: NSTableView? {
        func find(_ view: NSView) -> NSTableView? {
            // A JSON Viewer is an outline view's delegate, so look through NSOutlineView.
            if let table = view as? NSTableView, !((table as? NSOutlineView)?.delegate is JSONViewer) { return table }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        return find(inspectorView)
    }

    /// Selects an entry's range in the Input, rings it and scrolls to it.
    private func reveal(_ entry: InspectorEntry) {
        showSelectionInInput()
        let length = (textView.string as NSString).length
        guard NSMaxRange(entry.range) <= length else { return }
        textView.setSelectedRange(entry.range)
        textView.scrollRangeToVisible(entry.range)
    }

    // MARK: Split view

    private func makeSplitView() -> NSSplitView {
        let splitView = InvisibleDividerSplitView()
        splitView.isVertical = true
        splitView.delegate = self
        splitView.addArrangedSubview(inputScrollView)
        splitView.addArrangedSubview(inspectorView)
        // Resizing the window resizes the Input; the Inspector keeps its width.
        splitView.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow + 1, forSubviewAt: 1)
        inspectorView.isHidden = true
        return splitView
    }

    private var inspectorWidth: CGFloat {
        let saved = UserDefaults.standard.double(forKey: Self.inspectorWidthKey)
        return saved > 0 ? saved : 440
    }

    /// Shows the Inspector at its remembered width, or hides it.
    private func setInspectorShown(_ shown: Bool) {
        guard inspectorView.isHidden == shown else { return }
        isPlacingDivider = true
        defer { isPlacingDivider = false }
        inspectorView.isHidden = !shown
        // Before the first show the split view hasn't been sized yet.
        panel.contentView?.layoutSubtreeIfNeeded()
        splitView.adjustSubviews()
        if shown {
            let width = min(inspectorWidth, splitView.bounds.width - 200)
            splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: 0)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        max(proposed, 200)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        min(proposed, splitView.bounds.width - 320)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // Only a drag of the divider changes the remembered width; window resizes don't.
        guard !isPlacingDivider, !inspectorView.isHidden, notification.userInfo?["NSSplitViewDividerIndex"] != nil
        else { return }
        UserDefaults.standard.set(Double(inspectorView.frame.width), forKey: Self.inspectorWidthKey)
    }

    // MARK: Window

    /// The window's corner radius; the Inspector pane (18) and its rows and cards
    /// (10) nest inside it, each inset 8.
    static let cornerRadius: CGFloat = 26

    private func makePanel() -> NSWindow {
        let panel = PanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The main window: traffic lights, a full screen of its own, no title text
        // (the header says what it holds).
        panel.title = "textier"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        // An empty unified toolbar makes the title bar the header's height, so the
        // traffic lights sit level with the header's buttons.
        panel.toolbar = NSToolbar(identifier: "textier.Main")
        panel.toolbarStyle = .unified
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 560, height: 280)
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.model = model

        model.onInspectionChange = { [weak self] in self?.inspectionDidChange($0) }
        SettingsWindowController.panelInput = { [weak self] in self?.textView.string ?? "" }
        model.onSelectEntry = { [weak self] in self?.reveal($0) }
        model.onHighlightingChange = { [weak self] in self?.textView.highlighting = $0 }
        model.onWrapChange = { [weak self] in self?.textView.wrapsLines = $0 }
        // Focus moves through AppKit's first responder, which SwiftUI follows. The
        // window is reached through `self`: capturing it here would keep it, and
        // the model it shows, alive in a cycle.
        model.onFocusInput = { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.textView)
        }
        model.onFocusList = { [weak self] in
            guard let self, let list = self.entryList else { return }
            self.panel.makeFirstResponder(list)
        }

        // The frosted background; the window rounds its corners and draws its edge.
        let lights = panel.standardWindowButton(.zoomButton).map { $0.frame.maxX } ?? 70
        let background = NSVisualEffectView.frosted(around: NSHostingView(rootView: PanelView(
            model: model, split: splitView, leadingInset: lights + 8
        )))
        panel.contentView = background
        focusObservation = panel.observe(\.firstResponder, options: [.new]) { [weak self] panel, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let list = self.entryList
                self.model.listHasFocus = list != nil && panel.firstResponder === list
            }
        }
        // Restores the last size; the window is centered when it opens.
        panel.setFrameAutosaveName("textier.Panel")
        return panel
    }

    /// The header badge's warnings: config, theme, shortcut and editor warnings, plus
    /// a note when the last capture found no selection for lack of Accessibility.
    func updateWarnings() {
        var warnings = AppConfig.store.warnings.map(\.message)
        if SelectionCapture.lacksAccessibility {
            warnings.insert(
                "Accessibility is off, so the shortcut can't read your selection. "
                    + "Grant it in System Settings → Privacy & Security → Accessibility.",
                at: 0
            )
        }
        model.setWarnings(warnings)
    }
}

/// The Panel's window, textier's main window. Hides on Esc, from the Input as from
/// anywhere else (in full screen, Esc leaves full screen as usual), and handles the
/// Panel's shortcuts: ⌘E toggles Highlighting, ⌘L switches the Inspector between
/// tabs and one list, ⌘1–⌘9 switch Inspector tabs, ⌘⇧P pops the selected entry
/// out, ⌘, opens Settings. Caps Lock and the keypad don't change a shortcut.
private final class PanelWindow: NSWindow {
    weak var model: PanelModel?

    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            super.cancelOperation(sender)
        } else {
            orderOut(sender)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let model, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch (flags, key) {
        case ([.command], "e"):
            model.highlighting.toggle()
        case ([.command], "l"):
            model.layout = model.layout == .tabs ? .list : .tabs
        case ([.command, .shift], "p"):
            model.popOut()
        case ([.command], ","):
            SettingsWindowController.show()
        case ([.command], _) where key.count == 1 && ("1"..."9").contains(key) && model.selectTab(number: Int(key)!):
            break
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

/// A split view whose divider draws nothing but can still be dragged; it's the
/// 8 pt gap between the Input and the Inspector pane.
private final class InvisibleDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 8 }
    override func drawDivider(in rect: NSRect) {}
}

/// A scroll view whose content fades out at an edge while there's more of it
/// scrolled past that edge, in place of a divider line. Unscrolled content (the
/// first line, the last) is never faded.
final class FadingScrollView: NSScrollView {
    private let fade = CAGradientLayer()
    /// How far the fade reaches in from each edge.
    var fadeLength: CGFloat = 22

    /// Which edges fade now: those with content scrolled past them.
    private(set) var fadingEdges: (top: Bool, bottom: Bool) = (false, false)

    // Not `documentView`: AppKit reads that from its scrolling thread, and an
    // override here would be main-actor isolated and trap there.
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFade()
        // The Input's pointing-hand rects cover only the pills in view.
        if let document = clipView.documentView { window?.invalidateCursorRects(for: document) }
    }

    override func layout() {
        super.layout()
        updateFade()
    }

    override func tile() {
        super.tile()
        updateFade()
    }

    private func updateFade() {
        wantsLayer = true
        guard let layer, bounds.height > 0 else { return }
        let visible = contentView.bounds
        let content = documentView?.frame.height ?? 0
        fadingEdges = (visible.minY > 1, content - visible.maxY > 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let edge = Double(min(0.5, fadeLength / bounds.height))
        fade.colors = [
            (fadingEdges.top ? NSColor.clear : NSColor.black).cgColor, NSColor.black.cgColor,
            NSColor.black.cgColor, (fadingEdges.bottom ? NSColor.clear : NSColor.black).cgColor,
        ]
        fade.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        fade.frame = layer.bounds
        layer.mask = fade
        CATransaction.commit()
    }
}
