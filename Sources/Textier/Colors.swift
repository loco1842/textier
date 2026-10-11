import AppKit
import SwiftUI
import TextierCore

extension NSColor {
    /// A `#RRGGBB` or `#RRGGBBAA` value, as the config and themes write colors.
    convenience init?(hex: String) {
        guard hex.hasPrefix("#"), let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        let digits = hex.count - 1
        guard digits == 6 || digits == 8 else { return nil }
        let rgba = digits == 6 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt64) -> CGFloat { CGFloat((rgba >> shift) & 0xFF) / 255 }
        self.init(srgbRed: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    /// A color that resolves to `light` or `dark` with the drawing appearance.
    convenience init(light: NSColor, dark: NSColor) {
        self.init(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// One of a Pattern color's roles (`ColorRoles`), following the appearance.
    convenience init(patternColor: PatternColor, role: KeyPath<ColorRoles, String>) {
        func resolve(_ appearance: Appearance) -> NSColor {
            NSColor(hex: patternColor.roles(in: appearance)[keyPath: role]) ?? .systemBlue
        }
        self.init(light: resolve(.light), dark: resolve(.dark))
    }

    /// A theme's style color for the current appearance, from the light and dark themes.
    convenience init(lightHex: String, darkHex: String) {
        self.init(light: NSColor(hex: lightHex) ?? .labelColor, dark: NSColor(hex: darkHex) ?? .labelColor)
    }

    /// The themes' foreground, following the appearance: text no token color covers.
    @MainActor static var themeForeground: NSColor {
        themeForeground(alpha: 1, light: AppConfig.store.lightTheme, dark: AppConfig.store.darkTheme)
    }

    /// Indices and `{3 keys}`-style summaries: the themes' foreground, faded.
    @MainActor static var themeSecondaryForeground: NSColor {
        themeForeground(alpha: 0.6, light: AppConfig.store.lightTheme, dark: AppConfig.store.darkTheme)
    }

    /// A selected row or selected text in the JSON card: a faint wash of the
    /// themes' foreground.
    static func themeSelection(light: Theme, dark: Theme) -> NSColor {
        themeForeground(alpha: 0.16, light: light, dark: dark)
    }

    private static func themeForeground(alpha: CGFloat, light: Theme, dark: Theme) -> NSColor {
        NSColor(
            light: (NSColor(hex: light.foreground) ?? .labelColor).withAlphaComponent(alpha),
            dark: (NSColor(hex: dark.foreground) ?? .labelColor).withAlphaComponent(alpha)
        )
    }

    /// `#rrggbb`, or `#rrggbbaa` when not opaque, in sRGB, as the config writes colors.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        func byte(_ value: CGFloat) -> String { String(format: "%02x", Int((max(0, min(1, value)) * 255).rounded())) }
        let rgb = "#" + byte(color.redComponent) + byte(color.greenComponent) + byte(color.blueComponent)
        return color.alphaComponent < 1 ? rgb + byte(color.alphaComponent) : rgb
    }
}

extension Color {
    /// One of a Pattern color's roles, following the appearance.
    init(_ patternColor: PatternColor, _ role: KeyPath<ColorRoles, String>) {
        self.init(nsColor: NSColor(patternColor: patternColor, role: role))
    }
}
