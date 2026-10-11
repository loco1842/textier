import AppKit
import ApplicationServices

/// Captures the frontmost app's selection by simulating ⌘C, then puts the clipboard
/// back as it was. It never falls back to the clipboard: no selection is no text.
/// Call it before textier activates, so the selection still belongs to the
/// frontmost app.
@MainActor
enum SelectionCapture {
    private static let copyTimeout = Duration.milliseconds(200)
    private static let explainedKey = "didExplainAccessibility"

    /// Whether the last capture found no selection because textier lacks the
    /// Accessibility permission, which macOS also drops when an ad-hoc build changes.
    private(set) static var lacksAccessibility = false

    /// The selected text; nil when nothing is selected, or textier can't simulate a
    /// copy. The user's pasteboard is restored after the simulated copy.
    static func capture() async -> String? {
        let pasteboard = NSPasteboard.general
        lateCopyWatch?.invalidate()
        lateCopyWatch = nil
        // With textier frontmost (the Panel, a Match Window), its own selection is
        // read directly: a ⌘C would only copy it.
        guard !NSApp.isActive else {
            lacksAccessibility = false
            return ownSelection()
        }
        lacksAccessibility = !canSimulateCopy()
        guard !lacksAccessibility else { return nil }

        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        postCommandC()

        let deadline = ContinuousClock.now + copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard pasteboard.changeCount != before else {
            restoreAfterLateCopy(saved, from: before)
            return nil
        }

        // A password manager's field copies concealed: it isn't shown.
        let selection = pasteboard.isConcealed ? nil : pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return selection.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The text selected in textier's key window (or `window`), if it's a window
    /// (the Panel, a Match Window) with a text view focused.
    static func ownSelection(in window: NSWindow? = NSApp.keyWindow) -> String? {
        guard let window, window.styleMask.contains(.titled),
              let textView = window.firstResponder as? NSTextView
        else { return nil }
        let text = textView.string as NSString
        let selected = textView.selectedRanges.map { text.substring(with: $0.rangeValue) }.joined(separator: "\n")
        return selected.isEmpty ? nil : selected
    }

    /// How long after the deadline a slow app's copy is still taken for the ⌘C.
    private static let lateCopyWindow: TimeInterval = 1
    private static var lateCopyWatch: Timer?

    /// The ⌘C may still land after the deadline (an app that's busy, in a VM or
    /// over remote desktop): the popover already says nothing was selected, but
    /// the user's clipboard would be left holding the selection. So for a moment
    /// longer the clipboard is watched, and if it changes once, and not by
    /// textier's own copy (`lastOwnCopy`, kept for `Effects.pasteboard`, which is
    /// the general pasteboard outside the app tests), it's put back as it was. The
    /// late selection isn't shown: the popover is showing already. A second change, a
    /// new capture or the end of the window stops the watch.
    private static func restoreAfterLateCopy(_ saved: [[NSPasteboard.PasteboardType: Data]], from before: Int) {
        let end = Date().addingTimeInterval(lateCopyWindow)
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let pasteboard = NSPasteboard.general
                let count = pasteboard.changeCount
                if count == before, Date() < end { return }
                if count == before + 1, count != lastOwnCopy { restore(saved, to: pasteboard) }
                lateCopyWatch?.invalidate()
                lateCopyWatch = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        lateCopyWatch = timer
    }

    /// Whether textier has the Accessibility permission. The first time it doesn't,
    /// explains why it wants it and opens the system prompt; after that it stays quiet.
    private static func canSimulateCopy() -> Bool {
        if AXIsProcessTrusted() { return true }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: explainedKey) else { return false }
        defaults.set(true, forKey: explainedKey)

        let alert = NSAlert()
        alert.messageText = "textier needs Accessibility access"
        alert.informativeText = """
            To grab the text you have selected, textier presses ⌘C for you, which macOS \
            only allows with the Accessibility permission. Until it's granted, the \
            shortcut can't read your selection.
            """
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        alert.runModal()

        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 imports as a mutable global.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(8) // kVK_ANSI_C
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: keyDown)
            // Explicit flags, so the shortcut's still-held ⌃⌥ don't turn this into ⌃⌥⌘C.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    /// Puts back the clipboard as saved before the ⌘C.
    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        })
    }
}

extension NSPasteboard {
    /// Whether the pasteboard holds a copy a password manager marked concealed or
    /// transient (the nspasteboard.org markers), which the shortcut never shows.
    var isConcealed: Bool {
        let types = types ?? []
        return types.contains(Self.concealedType) || types.contains(Self.transientType)
    }

    private static let concealedType = PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = PasteboardType("org.nspasteboard.TransientType")
}
