import AppKit
import SwiftUI

/// The Settings window. There is one at most: showing it again brings it to the
/// front, and closing it lets it go, so the next show starts from the config file.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// The open window, kept alive until it closes.
    private(set) static var current: SettingsWindowController?
    /// The Panel's Input, which the Pattern test box starts with; the Panel sets it.
    static var panelInput: () -> String = { "" }

    let window: NSWindow
    let model: SettingsModel

    /// Opens Settings, or brings the open window to the front, with the Panel's
    /// Input (its start, when it's long) in the Pattern test box.
    static func show() {
        let controller = current ?? SettingsWindowController(model: SettingsModel(store: AppConfig.store))
        if current == nil {
            current = controller
            controller.window.center()
        }
        let input = panelInput()
        if !input.isEmpty { controller.model.testInput = SettingsModel.testSample(of: input) }
        Effects.present(controller.window)
    }

    private init(model: SettingsModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "textier Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}
