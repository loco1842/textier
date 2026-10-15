import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
import TextierCore
@testable import Textier

/// Runs `body` with the app running, as it would be for real.
///
/// AppKit stops the main run loop when an event arrives while `NSApp.run()` isn't
/// running, and Swift Testing's async main exits when that loop stops. So the
/// first call starts `NSApp.run()` from a run loop block (not a main-queue job,
/// which would keep the main queue from draining), and every test then runs as a
/// main-queue job inside it.
@MainActor
func runInApp(_ body: @MainActor () throws -> Void) async throws {
    _ = NSApplication.shared
    if !NSApp.isRunning {
        NSApp.setActivationPolicy(.accessory)
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { NSApp.run() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        while !NSApp.isRunning { try await Task.sleep(for: .milliseconds(10)) }
    }
    try body()
}

/// The app with one Panel, a config file in a temporary folder, and the outside
/// world (pasteboard, browser, editor, the system-wide shortcut) replaced by
/// recorders. Use it inside `runInApp`.
@MainActor
final class AppHarness {
    let folder: URL
    let store: ConfigStore
    let controller = PanelController()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("textier.tests.\(UUID().uuidString)"))
    private(set) var openedURLs: [URL] = []
    /// What the editor was asked to open: the path, and the line when there was one.
    private(set) var openedFiles: [FileLocation] = []
    /// Set to make the editor fail with this reason, as a command that won't run does.
    var editorFailure: String?
    /// Files the editor's fallback opened with their default app, and showed in Finder.
    private(set) var openedWithDefaultApp: [URL] = []
    private(set) var revealedInFinder: [URL] = []
    /// Every shortcut the app tried to register, in order.
    private(set) var registeredShortcuts: [Shortcut] = []
    /// Shortcuts another app holds, so registering them fails.
    var takenShortcuts: [Shortcut] = []

    /// `config` is the config file's text; nil writes the defaults, as a first launch does.
    init(config: String? = nil) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("textier-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("config.json")
        if let config { try Data(config.utf8).write(to: fileURL) }
        store = ConfigStore(fileURL: fileURL)
        AppConfig.store = store
        store.onReload = { [controller] in controller.configDidChange() }
        store.shortcutRegistrar = ShortcutRegistrar { [weak self] in self?.register($0) ?? noErr }
        store.start()

        Effects.pasteboard = pasteboard
        Effects.openURL = { [weak self] in self?.openedURLs.append($0) }
        Effects.openFile = { [weak self] in self?.openFile($0, line: $1) }
        Effects.openWithDefaultApp = { [weak self] in self?.openedWithDefaultApp.append($0) }
        Effects.revealInFinder = { [weak self] in self?.revealedInFinder.append($0) }
        // No test reaches GitHub: one that checks for updates gives its Updater answers.
        Updater.shared.fetch = { _ in throw UpdateError.network("no network in the tests") }
        // Windows show as they would, but see-through, click-through and without
        // bringing the app forward, so a test run doesn't cover the screen or take
        // the keyboard from whoever is working meanwhile. (A capture for a visual
        // check puts `Effects.present` back to show them for real.)
        Effects.copiedLabelOrigin = { NSPoint(x: -10_000, y: -10_000) }
        Effects.present = { window in
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.makeKeyAndOrderFront(nil)
        }

        // NSTextView's tracking loop reads the real pointer, so stand in for it: a
        // press selects from its point to where `drag` says the mouse went up, and a
        // double-click selects a word.
        controller.textView.trackMouse = { [weak self] event in self?.track(event) }

        // Each run starts from the default Panel size and Inspector width.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame textier.Panel")
        UserDefaults.standard.removeObject(forKey: PanelController.inspectorWidthKey)
        UserDefaults.standard.removeObject(forKey: PanelModel.tabOrderKey)
        // The Panel's model was made before this ran, so put wrapping back by hand.
        controller.model.wrapsLines = true
    }

    /// Closes the Panel, any Match Windows and Settings.
    func tearDown() {
        // A Settings window that outlives the test keeps the store, and the store
        // mustn't keep the Panel.
        store.onReload = {}
        // Closed, with their content let go: a titled window outlives its test (AppKit
        // keeps it), and its views would go on observing config reloads. Settings
        // windows are found by their content, as one the test closed itself has
        // already let its controller go.
        let settingsWindows = NSApp.windows.filter {
            $0.delegate is SettingsWindowController || $0.contentView is NSHostingView<SettingsView>
        }
        for window in [controller.panel] + MatchWindowController.openControllers.map(\.window) + settingsWindows {
            window.close()
            window.contentView = nil
        }
        // A named pasteboard otherwise lasts until logout.
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    var model: PanelModel { controller.model }
    var panel: NSWindow { controller.panel }
    var textView: InputTextView { controller.textView }
    var inspection: Inspection { model.inspection }
    var copied: String? { pasteboard.string(forType: .string) }
    var tabTitles: [String] { inspection.tabs.map(\.title) }
    /// The config file's text as it is on disk.
    var configText: String { (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? "" }
    var settingsWindow: SettingsWindowController? { SettingsWindowController.current }

    private func register(_ shortcut: Shortcut) -> OSStatus {
        registeredShortcuts.append(shortcut)
        return takenShortcuts.contains(shortcut) ? OSStatus(eventHotKeyExistsErr) : noErr
    }

    /// Records the file, and warns as `Editor` does when `editorFailure` is set.
    private func openFile(_ path: String, line: Int?) {
        openedFiles.append(FileLocation(path: path, line: line))
        guard let editorFailure else { return }
        store.editorWarning = ConfigWarning(
            "Couldn't run `\(store.config.editorCommand ?? "")` (\(editorFailure)); opened it with the default app"
        )
    }

    // MARK: Driving

    /// What a capture does: replaces the Input and shows the Panel.
    func capture(_ input: String) {
        controller.show(input: input)
        spin()
    }

    /// Lets the run loop turn: SwiftUI updates, debounced inspection, timers.
    func spin(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Waits past the Input's debounce so the Inspector catches up with an edit.
    func waitForInspection() {
        spin(0.35)
    }

    /// Selects `range` in the Input and types `text` over it, as the keyboard would.
    func type(_ text: String, replacing range: NSRange) {
        textView.setSelectedRange(range)
        textView.insertText(text, replacementRange: range)
        waitForInspection()
    }

    func type(_ text: String, at location: Int) {
        type(text, replacing: NSRange(location: location, length: 0))
    }

    /// Writes the config file and reloads it, as saving it in an editor does.
    func writeConfig(_ text: String) throws {
        try Data(text.utf8).write(to: store.fileURL)
        store.reload()
        spin()
    }

    func writeConfig(_ config: Config) throws {
        try writeConfig(String(decoding: ConfigFile.encode(config), as: UTF8.self))
    }

    // MARK: Mouse

    /// The window point in the middle of `range`'s first glyph in the Input.
    func point(inInput range: NSRange) -> NSPoint {
        let layoutManager = textView.layoutManager!
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer!)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return textView.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    }

    /// The window point in the middle of the last glyph of `range` in the Input.
    func point(inInputEndOf range: NSRange) -> NSPoint {
        point(inInput: NSRange(location: NSMaxRange(range) - 1, length: 1))
    }

    func range(of text: String) -> NSRange {
        (textView.string as NSString).range(of: text)
    }

    /// Where the mouse goes up after the next press; nil for a click.
    private var dragEnd: NSPoint?

    private func track(_ event: NSEvent) {
        func index(_ point: NSPoint) -> Int {
            textView.characterIndexForInsertion(at: textView.convert(point, from: nil))
        }
        let start = index(event.locationInWindow)
        if event.clickCount == 2 {
            textView.setSelectedRange(textView.selectionRange(
                forProposedRange: NSRange(location: start, length: 0), granularity: .selectByWord
            ))
            return
        }
        let end = dragEnd.map(index) ?? start
        dragEnd = nil
        textView.setSelectedRange(NSRange(location: min(start, end), length: abs(end - start)))
    }

    func mouseEvent(
        _ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow? = nil
    ) -> NSEvent {
        let window = window ?? panel
        return NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
        )!
    }

    /// A click in the Input: the mouse goes down and up at the same point.
    func click(_ point: NSPoint, clickCount: Int = 1) {
        textView.mouseDown(with: mouseEvent(.leftMouseDown, at: point, clickCount: clickCount))
        spin()
    }

    func click(onText text: String) {
        click(point(inInput: range(of: text)))
    }

    /// A click with modifiers held, ⌘ (the Match click's default) unless given.
    func commandClick(onText text: String, modifiers: NSEvent.ModifierFlags = [.command]) {
        textView.mouseDown(with: mouseEvent(.leftMouseDown, at: point(inInput: range(of: text)), modifiers: modifiers))
        spin()
    }

    /// A double-click: the first click, then the second with a click count of 2.
    func doubleClick(onText text: String) {
        let point = point(inInput: range(of: text))
        click(point)
        click(point, clickCount: 2)
    }

    /// A press at `start`, a drag to `end`, and a release there.
    func drag(from start: NSPoint, to end: NSPoint) {
        dragEnd = end
        textView.mouseDown(with: mouseEvent(.leftMouseDown, at: start))
        spin()
    }

    // MARK: Keyboard

    /// A key press of `characters`; its key code is the key's (`ShortcutKeys`) unless given.
    func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16? = nil) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: keyCode ?? UInt16(ShortcutKeys.codes[characters.lowercased()] ?? 0)
        )!
    }

    /// A ⌘-shortcut, as the menu-less Panel receives it. Returns whether it was handled.
    @discardableResult
    func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags = [.command]) -> Bool {
        let handled = panel.performKeyEquivalent(with: keyEvent(key, modifiers: modifiers))
        spin()
        return handled
    }

    /// A key press delivered to the first responder.
    func press(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        panel.sendEvent(keyEvent(characters, modifiers: modifiers, keyCode: keyCode))
        spin(0.1)
    }

    func pressDown() { press(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, modifiers: [.function, .numericPad]) }
    func pressUp() { press(String(UnicodeScalar(NSUpArrowFunctionKey)!), keyCode: 126, modifiers: [.function, .numericPad]) }
    func pressReturn() { press("\r", keyCode: 36) }
    func pressTab() { press("\t", keyCode: 48) }

    /// Whether keyboard focus is somewhere in the Inspector.
    var inspectorHasFocus: Bool {
        guard let responder = panel.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: controller.inspectorView)
    }

    // MARK: Inspector

    /// Selects the `index`th entry of the tab titled `title`, as clicking its row does.
    func select(_ title: String, _ index: Int) throws {
        let tab = try #require(inspection.tabs.first { $0.title == title })
        model.select(EntryID(tab: tab.id, index: index))
        spin()
    }

    var selectedTabTitle: String? { model.selectedTab?.title }

    /// The Action bar's button titles for the selected entry.
    var actionBar: [String] {
        guard let entry = model.selectedEntry else { return [] }
        return entry.barItems(isPlainText: model.isPlainTextSelected, inMatchWindow: false).map(\.title)
    }

    /// Clicks the Action bar button titled `title`.
    func runAction(_ title: String) throws {
        let entry = try #require(model.selectedEntry)
        let item = try #require(
            entry.barItems(isPlainText: model.isPlainTextSelected, inMatchWindow: false).first { $0.title == title }
        )
        model.run(item, on: entry)
        spin()
    }

    /// The JSON Viewer's outline in the Panel (or in `window`), once a JSON entry is shown.
    func outlineView(in window: NSWindow? = nil) -> NSOutlineView? {
        func find(_ view: NSView) -> NSOutlineView? {
            if let outline = view as? NSOutlineView, outline.delegate is JSONViewer { return outline }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        return (window ?? panel).contentView.flatMap(find)
    }

    var matchWindows: [MatchWindowController] { MatchWindowController.openControllers }
}

extension NSOutlineView {
    var viewer: JSONViewer { delegate as! JSONViewer }

    /// The row whose key path is `path` (`backtrace[0].file`; "" is the root).
    func row(keyPath path: String) -> Int? {
        (0..<numberOfRows).first { (item(atRow: $0) as? JSONNode)?.keyPathString == path }
    }

    func node(keyPath path: String) -> JSONNode? {
        row(keyPath: path).flatMap { item(atRow: $0) as? JSONNode }
    }
}

/// The Laravel/Monolog line from the grilling session, as in the core tests.
enum AppFixtures {
    static let monologLine = #"""
    [2026-10-07 11:17:10] develop.WARNING: [REPOSITORY SCOPE LEAK] __call invoked with non-empty scopeQueries {"url":"http://app.bo.test/player/api/v1/signin","repository":"Modules\\Notification\\Repositories\\EmailTemplateRepository","method":"where","scope_count":1,"caller_file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php","caller_line":118,"caller_function":"findActiveTemplate","backtrace":[{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php","line":80,"function":"__call"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php","line":118,"function":"findActiveTemplate"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":603,"function":"shouldQueue"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":552,"function":"handlerWantsToBeQueued"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":479,"function":"Illuminate\\Events\\{closure}"}]}
    """#

    static let backtraceFile = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php"
    static let dispatcherFile = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php"
    static let callerFile = "/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php"

    static var jsonPayload: String {
        String(monologLine[monologLine.range(of: #"{"url""#)!.lowerBound...])
    }
}
