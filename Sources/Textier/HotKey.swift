import Carbon.HIToolbox
import TextierCore

extension Shortcut {
    /// The `kVK_*` virtual key code for `key`, which names a physical key on an
    /// ANSI layout; nil only if `Shortcut.keys` grew without this table.
    fileprivate var carbonKeyCode: UInt32? {
        let codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
            "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
            "space": kVK_Space,
        ]
        return codes[key].map(UInt32.init)
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
