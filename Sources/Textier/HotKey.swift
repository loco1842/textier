import Carbon.HIToolbox
import TextierCore

extension Shortcut {
    /// The `kVK_*` virtual key code for `key`, which names a physical key on an
    /// ANSI layout; nil only if `Shortcut.keys` grew without this table.
    fileprivate var carbonKeyCode: UInt32? {
        ShortcutKeys.codes[key].map(UInt32.init)
    }

    fileprivate var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}

/// One system-wide shortcut, registered with Carbon so it fires while another app is
/// frontmost. Registering needs no Accessibility permission. Re-registering replaces
/// the previous shortcut. Lives for the app's lifetime.
@MainActor
final class HotKey {
    var onPress: () -> Void = {}

    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?

    /// Registers `shortcut`, replacing any earlier one. Returns the Carbon status;
    /// `eventHotKeyExistsErr` means another app already holds the shortcut.
    @discardableResult
    func register(_ shortcut: Shortcut) -> OSStatus {
        unregister()
        guard let keyCode = shortcut.carbonKeyCode else { return OSStatus(paramErr) }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x7478_7472) /* "txtr" */, id: 1)
        return RegisterEventHotKey(
            keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &registration
        )
    }

    func unregister() {
        guard let registration else { return }
        UnregisterEventHotKey(registration)
        self.registration = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                // Carbon delivers application-target events on the main thread.
                guard let userData else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress()
                }
                return noErr
            },
            1,
            &pressed,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
