// Sources/AutoCIApp/DesignTokens.swift
import SwiftUI
import AppKit

/// Adaptive color tokens for the panel. Everything resolves correctly in both
/// Light and Dark mode — no hardcoded white/black. Surfaces use primary.opacity
/// (black-tint in light, white-tint in dark); state colors use appearance-aware
/// NSColor dynamic providers with explicit, contrast-checked light/dark values.
enum ACColor {
    // Text
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary  = Color(nsColor: .tertiaryLabelColor)

    // Surfaces (adaptive via primary tint)
    static let fillQuaternary = Color.primary.opacity(0.05) // tiles, chips
    static let fillSecondary  = Color.primary.opacity(0.07) // icon wells
    static let fillTertiary   = Color.primary.opacity(0.09) // active tile, action buttons
    static let fillHover      = Color.primary.opacity(0.13) // hover

    // Strokes / separators
    static let strokeSubtle   = Color(nsColor: .separatorColor)

    // Elevated card surface — lighter than the (frosted) panel so cards lift off it.
    // Light: opaque white card on the grey material; Dark: a grey lifted above the dark window.
    static let surfaceCard = Color(nsColor: dyn(
        light: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.95),
        dark:  NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.10)))
    // Soft drop shadow under cards (subtle; lighter in dark to avoid mud).
    static let cardShadow = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12),
        dark:  NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)))

    // State colors (appearance-aware)
    static let stateIdle = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.42, green: 0.42, blue: 0.44, alpha: 1),
        dark:  NSColor(srgbRed: 0.55, green: 0.55, blue: 0.57, alpha: 1)))
    static let stateWatching = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.00, green: 0.44, blue: 0.90, alpha: 1),
        dark:  NSColor(srgbRed: 0.28, green: 0.64, blue: 1.00, alpha: 1)))
    static let stateFixing = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.85, green: 0.44, blue: 0.00, alpha: 1),
        dark:  NSColor(srgbRed: 1.00, green: 0.62, blue: 0.14, alpha: 1)))
    static let stateFixed = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.13, green: 0.60, blue: 0.20, alpha: 1),
        dark:  NSColor(srgbRed: 0.30, green: 0.84, blue: 0.40, alpha: 1)))
    static let stateAttention = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.82, green: 0.09, blue: 0.09, alpha: 1),
        dark:  NSColor(srgbRed: 1.00, green: 0.36, blue: 0.36, alpha: 1)))

    // Destructive button surface
    static let destructiveFill = Color(nsColor: dyn(
        light: NSColor(srgbRed: 0.82, green: 0.09, blue: 0.09, alpha: 0.10),
        dark:  NSColor(srgbRed: 0.75, green: 0.12, blue: 0.12, alpha: 0.28)))
    static let destructiveText = stateAttention

    /// Build an appearance-aware NSColor from explicit light/dark values.
    private static func dyn(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}

/// Frosted system material behind the whole panel — gives the native popover depth
/// (Control Center / menu-bar popover look) so elevated cards read against it.
struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
