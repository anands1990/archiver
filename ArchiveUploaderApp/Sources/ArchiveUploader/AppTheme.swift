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

    static var mutedText: Color {
        Color.secondary.opacity(0.5)
    }

    static var error: Color {
        Color.red.opacity(0.8)
    }
}
