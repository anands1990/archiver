import SwiftUI

/// Shared motion vocabulary.
///
/// Rules of the house: UI feedback stays fast (under ~200ms) so the app feels
/// like it is listening; decoration (shimmer, sparkle) runs longer because it
/// is *watched*, not waited on. Every looping or one-shot animation is skipped
/// under Reduce Motion.
enum Motion {
    /// Instant response — press feedback, small state flips.
    static let quick: Animation = .snappy(duration: 0.14, extraBounce: 0)

    /// Standard enter/exit for panels, rows and popovers.
    static let standard: Animation = .easeOut(duration: 0.22)

    /// Content shifts that need a little settle — list inserts, panel swaps.
    static let settle: Animation = .spring(duration: 0.34, bounce: 0.16)

    /// Constant looping decoration.
    static let loop: Animation = .linear(duration: 1.3)
}

// MARK: - Press feedback

/// Every tappable control scales down slightly on press. It is the cheapest way
/// to make an interface feel responsive: the user gets physical confirmation
/// that the click landed, before anything has actually happened yet.
struct PressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressFeedbackButtonStyle {
    /// `.buttonStyle(.pressFeedback)`
    static var pressFeedback: PressFeedbackButtonStyle { .init() }
}

// MARK: - Shimmer

/// A translucent band sweeping across a view. Used on the progress fill to say
/// "this is actively moving" without adding another spinner to look at.
struct ShimmerOverlay: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweep = false

    /// Width of the travelling band.
    var band: CGFloat = 48
    var tint = Color.white

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.overlay {
                GeometryReader { geo in
                    let travel = geo.size.width + band * 2
                    Capsule()
                        .fill(tint)
                        .frame(width: band)
                        .blur(radius: 4)
                        .offset(x: -geo.size.width / 2 - band + (sweep ? travel : 0))
                }
                .allowsHitTesting(false)
                .clipped()
            }
            .onAppear {
                withAnimation(Motion.loop.repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
        }
    }
}

extension View {
    /// Overlays a travelling highlight, clipped to the view's own shape.
    func shimmer(band: CGFloat = 48, tint: Color = .white) -> some View {
        modifier(ShimmerOverlay(band: band, tint: tint))
    }
}

// MARK: - Sparkle

/// One-shot celebratory burst, fired when a book finishes uploading.
/// Purely decorative — nothing depends on it happening.
struct SparkleBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint = AppTheme.celebrate
    var count = 7

    @State private var ignited = false

    private var angles: [Double] {
        (0..<count).map { index in
            Double(index) * (360.0 / Double(count))
        }
    }

    var body: some View {
        ZStack {
            ForEach(angles.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: 4)
                    .rotationEffect(.degrees(angles[index]))
                    .offset(y: ignited ? -11 : -4)
                    .opacity(ignited ? 0 : 1)
                    .scaleEffect(ignited ? 0.5 : 1.15)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                ignited = true
            }
        }
    }
}

// MARK: - Pulse

/// A soft breathing dot. Marks "the sidecar is up" so the state reads at a
/// glance without needing to read the label next to it.
struct PulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint = Color.green

    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 7, height: 7)
            .scaleEffect(breathing ? 1.3 : 1)
            .opacity(breathing ? 0.6 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

// MARK: - Draw-in checkmark

/// A checkmark that draws itself instead of popping in. Small detail, but it is
/// the difference between "a status changed" and "a job finished".
struct DrawInCheckmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint = AppTheme.celebrate

    @State private var drawn = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .scaleEffect(drawn ? 1 : 0.4)
            .opacity(drawn ? 1 : 0)
            .onAppear {
                guard !reduceMotion else {
                    drawn = true
                    return
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
                    drawn = true
                }
            }
    }
}

// MARK: - Gentle float

/// A slow vertical drift for the empty state. The only animation on screen
/// when there is nothing to do, so it has to be quiet.
struct GentleFloat: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var distance: CGFloat = 3

    @State private var drifting = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .offset(y: drifting ? -distance : distance)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        drifting = true
                    }
                }
        }
    }
}

extension View {
    func gentleFloat(distance: CGFloat = 3) -> some View {
        modifier(GentleFloat(distance: distance))
    }
}
