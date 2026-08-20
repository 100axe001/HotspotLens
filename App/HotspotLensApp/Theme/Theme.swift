import SwiftUI

/// Single source of truth for HotspotLens's warm visual identity. Every
/// view should reach for `Theme.*` rather than ad-hoc colors/fonts, so the
/// light/dark warm palettes and type scale stay consistent everywhere
/// (menu bar popover and dashboard alike).
enum Theme {
    // MARK: - Backgrounds

    /// Cream in light mode, warm charcoal-brown (not pure black) in dark.
    static let background = Color("ThemeBackground", bundle: .main)
    static let surface = Color("ThemeSurface", bundle: .main)
    static let surfaceElevated = Color("ThemeSurfaceElevated", bundle: .main)

    // MARK: - Text

    static let textPrimary = Color("ThemeTextPrimary", bundle: .main)
    static let textSecondary = Color("ThemeTextSecondary", bundle: .main)

    // MARK: - Accents

    /// Warm amber/terracotta -- primary actions, active states, "device
    /// connected" indicator. Never used for destructive actions.
    static let accent = Color("ThemeAccent", bundle: .main)
    static let accentSubtle = Color("ThemeAccentSubtle", bundle: .main)

    /// Conventional red, reserved *only* for blocking/destructive actions
    /// so it doesn't get lost among the warm palette and always reads as
    /// "this is different from the rest of the UI."
    static let destructive = Color("ThemeDestructive", bundle: .main)

    static let border = Color("ThemeBorder", bundle: .main)

    // MARK: - Type scale

    static let titleFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.caption, design: .rounded)
    static let monoCaptionFont = Font.system(.caption, design: .monospaced)

    // MARK: - Shape

    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 8
    static let cardPadding: CGFloat = 14
}

extension View {
    /// Standard rounded warm "card" container used throughout the dashboard
    /// and menu bar popover.
    func themedCard() -> some View {
        self
            .padding(Theme.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
