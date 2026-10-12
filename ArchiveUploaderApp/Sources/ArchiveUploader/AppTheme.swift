import SwiftUI

/// Archiver's visual system. See DESIGN.md for the reasoning.
///
/// The whole palette resolves through system colours so it adapts to light,
/// dark, reduced transparency and increased contrast for free. Nothing here is
/// a hardcoded value — that is the design, not an oversight.
enum AppTheme {
    /// The panel backdrop.
    static var background: Color {
        Color(NSColor.controlBackgroundColor)
    }

    /// Card fills. Identical to background: elevation comes from borders, so a
    /// second fill colour never has to be reasoned about in dark mode.
    static var surface: Color {
        background
    }

    /// Interactive accent — the colour the user chose in System Settings.
    /// Using `labelColor` here instead would ignore their accent entirely.
    static var accent: Color {
        Color.accentColor
    }

    static let subtleBorder = Color.secondary.opacity(0.08)

    /// Completion. Semantic, so it stays legible in every appearance.
    static var celebrate: Color {
        Color.green
    }

    static var danger: Color {
        Color.red
    }

    /// A whisper of vertical shade behind the panel: enough depth to read as a
    /// surface, not enough to look like a gradient. Uses `Color.primary` at low
    /// opacity so it flips with appearance.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(NSColor.controlBackgroundColor), Color.primary.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Type scale

/// Semantic text styles, never hardcoded point sizes.
///
/// macOS is 13pt body with a 10pt recommended floor; `.caption` is the
/// smallest role used anywhere in the app.
enum TextStyle {
    /// Panel and section titles.
    static let title = Font.headline

    /// Primary content — task titles, field labels.
    static let body = Font.body

    /// Secondary content — descriptions.
    static let callout = Font.callout

    /// Row messages, status lines, settings values.
    static let footnote = Font.footnote

    /// Notes and help text. The smallest text in the app.
    static let caption = Font.caption

    /// Monospaced text for paths and model names.
    static let mono = Font.footnote.monospaced()
}

// MARK: - Spacing

enum Spacing {
    /// Panel gutter.
    static let gutter: CGFloat = 16
    /// Between groups.
    static let group: CGFloat = 16
    /// Between related controls.
    static let row: CGFloat = 8
    /// Inside a single control.
    static let tight: CGFloat = 4
}
