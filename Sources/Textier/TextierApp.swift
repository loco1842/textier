import AppKit
import SwiftUI
import TextierCore

@main
struct TextierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and the Selection Popover are a status item of
        // textier's own (`SelectionPopoverController`), which the shortcut can open.
        // A scene is required, so an empty one, never shown.
        MenuBarExtra("textier", systemImage: "text.magnifyingglass", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = PanelController()
    /// The menu bar icon and the Selection Popover, which opens its text in the Panel.
    private(set) lazy var popover = SelectionPopoverController(
        openInPanel: { [weak self] in self?.panel.show(input: $0) },
        openPanel: { [weak self] in self?.panel.show() }
    )
    private let hotKey = HotKey()
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bundle's LSUIElement does this too; repeated here so `swift run` has no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        hotKey.onPress = { [weak self] in self?.captureIntoPopover() }
        AppConfig.store.shortcutRegistrar = ShortcutRegistrar { [hotKey] in hotKey.register($0) }
        AppConfig.store.onReload = { [weak self] in
            self?.panel.configDidChange()
            self?.popover.model.configDidChange()
        }
        AppConfig.store.onWarningsChange = { [weak self] in
            self?.panel.updateWarnings()
            self?.popover.updateIcon()
        }
        AppConfig.store.start()
        Updater.shared.start()
        // The menu bar icon shows from launch.
        _ = popover
        Editor.prepare()
    }

    /// Shows the selection in the popover (in the Panel when the menu bar icon is
    /// out of sight), replacing what it held. Pressed again while the popover is
    /// open, it closes it.
    private func captureIntoPopover() {
        guard !isCapturing else { return }
        guard !popover.isShown else { return popover.close() }
        isCapturing = true
        Task {
            let selection = await SelectionCapture.capture()
            if !popover.show(selection: selection, lacksAccessibility: SelectionCapture.lacksAccessibility) {
                // No selection leaves the Panel's Input as it was.
                if let selection { panel.show(input: selection) } else { panel.show() }
            }
            isCapturing = false
        }
    }
}
