import SwiftUI

/// Shared motion vocabulary.
///
/// Rules of the house: everything a user *does* gets an immediate, snappy
/// response — press feedback, toggles, panel swaps — so the app feels like it
/// is listening. Anything longer is either a one-shot acknowledgement (a
/// completion pop) or decoration that plays once and then rests.
///
/// Nothing loops forever. A permanently repeating animation keeps re-rendering
/// the window for as long as the panel is open, which measured at ~100% of a
/// core and starved the main thread until the panel lost keyboard focus.
enum Motion {
    /// Instant response — press feedback, small state flips. Snappy, no bounce:
    /// the user is mid-gesture, so this must feel instant.
    static let quick: Animation = .snappy(duration: 0.12, extraBounce: 0)

    /// Discrete state changes — panel swaps, sheet entry, cards appearing.
    /// Fast, ease-out so movement starts immediately.
    static let standard: Animation = .easeOut(duration: 0.18)

    /// Content that needs to land rather than snap — list inserts. A small
    /// amount of bounce is what makes it feel physical.
    static let settle: Animation = .spring(duration: 0.3, bounce: 0.22)

    /// One-shot acknowledgement — a task finishing. Bouncier, because this is
    /// watched and celebrated, not waited on.
    static let pop: Animation = .spring(duration: 0.4, bounce: 0.42)
}

// MARK: - Press feedback

/// Every tappable control scales down slightly on press. It is the cheapest way
/// to make an interface feel responsive: the user gets physical confirmation
/// that the click landed, before anything has actually happened yet.
///
/// 0.96 reads as a deliberate press rather than an accidental jitter, and pairs
/// with a brief opacity dip so the control dims as it sinks.
struct PressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressFeedbackButtonStyle {
    /// `.buttonStyle(.pressFeedback)`
    static var pressFeedback: PressFeedbackButtonStyle { .init() }
}

// MARK: - Shimmer

/// A soft highlight sweeping across a view. Used on the progress fill to say
/// "this is actively moving" without adding another spinner to look at.
///
/// Deliberately built from a gradient rather than a blurred layer: a Gaussian
/// blur has to be re-rendered every frame in a window this small, which pinned
/// the main thread at ~100% CPU for as long as the progress card was on screen.
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
                    // A zero-width host (progress not started yet) would make
                    // the travel maths degenerate, so rest until there's room.
                    if geo.size.width > band {
                        let travel = geo.size.width + band * 2
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, tint, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: band)
                            .offset(x: -geo.size.width / 2 - band + (sweep ? travel : 0))
                            .onAppear { sweepOnce() }
                    }
                }
                .allowsHitTesting(false)
                .clipped()
            }
        }
    }

    /// One sweep when the bar appears, then rests.
    ///
    /// A permanently looping animation keeps re-rendering the window for as
    /// long as the panel is open — measured at ~15% of a core while idle, and
    /// enough to starve the main thread during long translations. The progress
    /// fill's own width animation already communicates movement; this is here
    /// only to greet the start of a job.
    private func sweepOnce() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.1)) { sweep = true }
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

/// A soft breathing dot. Marks "the sidecar is up".
///
/// Pulses a few times when it appears, then rests. A permanently looping dot
/// re-renders the window for as long as the panel is open, which is paid for
/// every time the user glances at it.
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
                // Three breaths (6 half-cycles), ending back at rest.
                withAnimation(.easeInOut(duration: 0.5).repeatCount(6, autoreverses: true)) {
                    breathing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        breathing = false
                    }
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

/// A slow vertical drift for the empty state.
///
/// One round trip on appear, then it rests — the only animation on screen when
/// there is nothing to do, so it has to be quiet in CPU terms as well as
/// visually, or the panel costs a core per minute of being open.
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
                    // Single round trip: 2 half-cycles of 1.8s.
                    withAnimation(.easeInOut(duration: 1.8).repeatCount(2, autoreverses: true)) {
                        drifting = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            drifting = false
                        }
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
