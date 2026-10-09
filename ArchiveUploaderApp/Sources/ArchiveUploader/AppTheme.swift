import SwiftUI

enum AppTheme {
    /// The single background color for the entire app — no layering, no color shifts
    static var background: Color {
        Color(NSColor.controlBackgroundColor)
    }

    /// Surface is identical to background; elevation is achieved with borders only
    static var surface: Color {
        background
    }

    /// A whisper of vertical shade behind the whole window: enough depth to read
    /// as a surface, not enough to look like a "gradient". Uses `Color.primary`
    /// at low opacity so it flips with the appearance — dark tint in light mode,
    /// light tint in dark mode — without a second palette to maintain.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(NSColor.controlBackgroundColor), Color.primary.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var border: Color {
        Color.secondary.opacity(0.12)
    }

    static var subtleBorder: Color {
        Color.secondary.opacity(0.08)
    }

    /// Monochrome accent: the system label color (black in light, white in dark)
    static var accent: Color {
        Color(NSColor.labelColor)
    }

    /// Reserved for celebration only — the sparkle burst and completion marks.
    /// Matches the app icon's warm orange so success feels like part of the
    /// product identity rather than a generic green tick.
    static var celebrate: Color {
        Color(red: 1.0, green: 0.62, blue: 0.18)
    }

    static var mutedText: Color {
        Color.secondary.opacity(0.5)
    }

    static var error: Color {
        Color.red.opacity(0.8)
    }
}
