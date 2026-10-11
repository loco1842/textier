import Foundation

/// Light or dark: which half of a `PatternColor` applies, and which pane it's read against.
public enum Appearance: Sendable, Equatable, CaseIterable {
    case light, dark
}

/// The colors the UI draws one Pattern with, in one appearance, as `#rrggbb` or
/// `#rrggbbaa` values.
public struct ColorRoles: Sendable, Equatable {
    /// A pill or tab at rest, and the selected row: the solid, translucent.
    public var tint: String
    /// Hover, the selected Match, chips.
    public var strongTint: String
    /// The selected tab, the primary Action, row bars, rings, the header's color bar.
    public var solid: String
    /// A pill's text and colored labels: the solid, darkened (light) or lightened
    /// (dark) until it reads at 6:1 on the strong tint over the pane, about where
    /// Radix's text shades sit (and over WCAG's 4.5:1).
    public var text: String
    /// Text on the solid: white when it reads at 3:1 there (the UI-component
    /// level), near-black otherwise.
    public var onSolid: String
}

/// The Inspector pane each appearance's colors are read against: the frosted
/// window with the pane's lighter layer over it.
public enum Pane {
    public static func color(in appearance: Appearance) -> String {
        switch appearance {
        case .light: "#f5f5f7"
        case .dark: "#2a2a30"
        }
    }
}

extension PatternColor {
    /// The roles this color draws with in `appearance`. A value written with its own
    /// alpha keeps it as the tint; the solid is always opaque. An unreadable value
    /// (the config reports it) draws as `Palette.fallback`.
    public func roles(in appearance: Appearance) -> ColorRoles {
        let hex = appearance == .light ? light : dark
        let fallback = appearance == .light ? Palette.fallback.light : Palette.fallback.dark
        let written = RGBColor(hex: hex) ?? RGBColor(hex: fallback)!
        let solid = written.opaque
        let (tintAlpha, strongAlpha) = (0.14, 0.28)
        let ownAlpha = written.alpha < 1 ? written.alpha : nil
        let tint = solid.with(alpha: ownAlpha ?? tintAlpha)
        let strongTint = solid.with(alpha: ownAlpha.map { min(1, $0 * 1.75) } ?? strongAlpha)

        let pane = RGBColor(hex: Pane.color(in: appearance))!
        let behindText = strongTint.composited(over: pane)
        let toward = appearance == .light ? RGBColor.black : RGBColor.white
        var text = solid
        var step = 0.0
        // A little over 6, so rounding to whole bytes can't take it under.
        while text.contrast(with: behindText) < 6.1, step < 1 {
            step += 0.02
            text = solid.mixed(with: toward, by: step)
        }

        let onSolid = RGBColor.white.contrast(with: solid) >= 3 ? RGBColor.white : RGBColor.nearBlack
        return ColorRoles(
            tint: tint.hex, strongTint: strongTint.hex, solid: solid.hex, text: text.hex, onSolid: onSolid.hex
        )
    }
}

/// An sRGB color with alpha, each channel 0…1, for working out contrast without AppKit.
public struct RGBColor: Sendable, Equatable {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#rrggbb` or `#rrggbbaa`.
    public init?(hex: String) {
        guard hex.hasPrefix("#"), [7, 9].contains(hex.count), let value = UInt64(hex.dropFirst(), radix: 16) else {
            return nil
        }
        let rgba = hex.count == 7 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt64) -> Double { Double((rgba >> shift) & 0xFF) / 255 }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    static let white = RGBColor(red: 1, green: 1, blue: 1)
    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let nearBlack = RGBColor(hex: "#1d1d1f")!

    /// `#rrggbb`, or `#rrggbbaa` when not opaque.
    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02x", Int((max(0, min(1, value)) * 255).rounded())) }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? rgb + byte(alpha) : rgb
    }

    /// WCAG relative luminance, ignoring alpha.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio with `other`, both taken as opaque.
    public func contrast(with other: RGBColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This color drawn over an opaque `background`.
    public func composited(over background: RGBColor) -> RGBColor {
        mixed(with: background, by: 1 - alpha).with(alpha: 1)
    }

    var opaque: RGBColor { with(alpha: 1) }

    func with(alpha: Double) -> RGBColor {
        RGBColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// `amount` of the way from this color to `other`, channel by channel.
    func mixed(with other: RGBColor, by amount: Double) -> RGBColor {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return RGBColor(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue), alpha: alpha)
    }
}
