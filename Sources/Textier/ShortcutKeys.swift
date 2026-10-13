import AppKit
import Carbon.HIToolbox
import SwiftUI
import TextierCore

/// Where a `Shortcut`'s key names meet the keyboard: the virtual key code of each
/// key it accepts (a physical key on an ANSI layout), both ways.
enum ShortcutKeys {
    static let codes: [String: Int] = {
        var codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon,
            "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "-": kVK_ANSI_Minus,
            "=": kVK_ANSI_Equal, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { codes["f\(index + 1)"] = code }
        return codes
    }()

    static let names: [Int: String] = Dictionary(uniqueKeysWithValues: codes.map { ($1, $0) })

    /// The modifiers of `flags` a Shortcut has; Caps Lock, Fn and the keypad aren't.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// The key name of a key press: what it types with no modifiers (so a letter
    /// follows the keyboard layout, as menus do, and ⇧⌘, is a comma), or for Space
    /// and the function keys, its key code.
    static func keyName(_ event: NSEvent) -> String? {
        if let name = names[Int(event.keyCode)], name == "space" || name.count > 1 { return name }
        if let typed = event.characters(byApplyingModifiers: [])?.lowercased(), Shortcut.keys.contains(typed) {
            return typed
        }
        return names[Int(event.keyCode)]
    }
}

extension Shortcut {
    /// The Shortcut a key press is, if it's one.
    init?(event: NSEvent) {
        guard let key = ShortcutKeys.keyName(event) else { return nil }
        self.init(modifiers: ShortcutKeys.modifiers(event.modifierFlags), key: key)
    }

    /// For a menu item: its key equivalent and modifier mask.
    var keyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        let key: String = switch self.key {
        case "space": " "
        case let name where name.hasPrefix("f") && name.count > 1:
            String(UnicodeScalar(NSF1FunctionKey + (Int(name.dropFirst()) ?? 1) - 1).map(Character.init) ?? " ")
        case let name: name
        }
        return (key, flags)
    }

    /// For SwiftUI's `.keyboardShortcut`; nil for a function key, which it can't take.
    var swiftUI: KeyboardShortcut? {
        var modifiers: SwiftUI.EventModifiers = []
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        switch key {
        case "space": return KeyboardShortcut(.space, modifiers: modifiers)
        case let name where name.count == 1: return KeyboardShortcut(KeyEquivalent(Character(name)), modifiers: modifiers)
        default: return nil
        }
    }

    /// Whether `flags` hold exactly these modifiers.
    static func matches(_ modifiers: Modifiers, _ flags: NSEvent.ModifierFlags) -> Bool {
        ShortcutKeys.modifiers(flags) == modifiers
    }
}
