import SwiftUI

enum NotchTheme {
    struct PomodoroTimerColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func interpolated(to target: Self, amount: Double) -> Self {
            let progress = min(max(amount, 0), 1)
            return Self(
                red: red + ((target.red - red) * progress),
                green: green + ((target.green - green) * progress),
                blue: blue + ((target.blue - blue) * progress)
            )
        }
    }

    private struct TagPaletteAnchor {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func lightened(by amount: Double) -> Color {
            Color(
                red: red + ((1 - red) * amount),
                green: green + ((1 - green) * amount),
                blue: blue + ((1 - blue) * amount)
            )
        }

        func darkened(by amount: Double) -> Color {
            Color(
                red: red * (1 - amount),
                green: green * (1 - amount),
                blue: blue * (1 - amount)
            )
        }
    }

    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 560
    static let headerHeight: CGFloat = 62
    /// Width of the concave fillets that merge the surface into the top screen edge.
    static let topFlare: CGFloat = 10
    /// Equal content width on either side of a hardware notch while a live activity is visible.
    static let collapsedActivityWingWidth: CGFloat = 116
    private static let primaryAccentComponents = PomodoroTimerColor(
        red: 1,
        green: 1,
        blue: 1
    )
    static let primaryAccent = primaryAccentComponents.color
    /// Completion remains the app's positive mint signal even when the
    /// general-purpose accent changes.
    static let completionAccent = Color(red: 0.23, green: 0.78, blue: 0.50)
    static let ink = Color(red: 0.022, green: 0.024, blue: 0.027)
    static let graphite = Color(red: 0.070, green: 0.074, blue: 0.080)
    static let raisedGraphite = Color(red: 0.110, green: 0.114, blue: 0.122)
    static let field = Color(red: 0.065, green: 0.067, blue: 0.072)
    static let control = Color.white.opacity(0.060)
    static let selectedControl = Color.white.opacity(0.135)
    static let selectedLedger = Color.white.opacity(0.055)
    static let hoveredLedger = Color.white.opacity(0.028)
    static let completedLedger = completionAccent.opacity(0.045)
    /// Specular highlight riding the crest of the completion wave.
    static let completionCrest = completionAccent.opacity(0.18)
    /// Additional warmth layered behind the crest; multiplied by (1 - progress)
    /// so the trail cools into completedLedger as the liquid settles.
    static let completionTrail = completionAccent.opacity(0.075)
    /// Extra fill layered over completedLedger while the flood is live
    /// (energy 1); cools away so the row rests at the quiet completed tint.
    static let completionFloodBoost = completionAccent.opacity(0.18)
    /// Tight unblurred glint riding the very front of the wave, inside the
    /// blurred completionCrest halo.
    static let completionCrestCore = completionAccent.opacity(0.42)
    /// Center color of the radial bloom that ignites behind the checkbox at
    /// the moment of completion.
    static let completionIgnitionGlow = completionAccent.opacity(0.45)
    static let controlStroke = Color.white.opacity(0.075)
    static let hairline = Color.white.opacity(0.065)
    static let primaryText = Color.white.opacity(0.90)
    static let secondaryText = Color.white.opacity(0.55)
    // Completed rows sit below the secondary/tertiary ramp on purpose: the
    // deeper dim is what makes the done state legible at a glance.
    static let completedPrimaryText = Color.white.opacity(0.24)
    static let completedSecondaryText = Color.white.opacity(0.18)
    // 0.48 keeps small timestamps/captions at ~4.5:1 over ink (AA); 0.39 measured ~3.1:1.
    static let tertiaryText = Color.white.opacity(0.48)
    static let dueAccent = Color(red: 0.48, green: 0.49, blue: 0.86)
    static let warning = Color.orange
    static let destructive = Color.red

    /// Maps the remaining share of a focus session from calm white through amber to red.
    static func pomodoroTimerColor(remaining: TimeInterval, duration: TimeInterval) -> PomodoroTimerColor {
        guard duration.isFinite, duration > 0, remaining.isFinite else {
            return pomodoroDestructive
        }

        let remainingFraction = min(max(remaining / duration, 0), 1)
        switch remainingFraction {
        case 0.5...:
            return primaryAccentComponents
        case 0.2...:
            let progress = (0.5 - remainingFraction) / 0.3
            return primaryAccentComponents.interpolated(to: pomodoroWarning, amount: progress)
        default:
            let progress = (0.2 - remainingFraction) / 0.2
            return pomodoroWarning.interpolated(to: pomodoroDestructive, amount: progress)
        }
    }

    private static let pomodoroWarning = PomodoroTimerColor(red: 1, green: 0.5, blue: 0)
    private static let pomodoroDestructive = PomodoroTimerColor(red: 1, green: 0, blue: 0)
    /// Bottom corner radius shared by every open surface state and the composer.
    static let surfaceBottomRadius: CGFloat = 24
    private static let tagPaletteAnchors = [
        TagPaletteAnchor(red: 0.31, green: 0.89, blue: 1.00),
        TagPaletteAnchor(red: 0.46, green: 0.42, blue: 1.00),
        TagPaletteAnchor(red: 0.93, green: 0.34, blue: 0.94),
        TagPaletteAnchor(red: 1.00, green: 0.42, blue: 0.55),
        TagPaletteAnchor(red: 1.00, green: 0.78, blue: 0.30),
        TagPaletteAnchor(red: 0.28, green: 0.94, blue: 0.65),
    ]
    static func tagPaletteIndex(seed: Double) -> Int {
        let normalized = seed - floor(seed)
        return Int(normalized * Double(tagPaletteAnchors.count)) % tagPaletteAnchors.count
    }

    static func tagTonalGradient(seed: Double) -> LinearGradient {
        let normalized = seed - floor(seed)
        let anchor = tagPaletteAnchors[tagPaletteIndex(seed: seed)]
        let reversesDirection = normalized >= 0.5
        return LinearGradient(
            colors: [
                anchor.lightened(by: 0.22),
                anchor.color,
                anchor.darkened(by: 0.16),
            ],
            startPoint: reversesDirection ? .bottomLeading : .topLeading,
            endPoint: reversesDirection ? .topTrailing : .bottomTrailing
        )
    }

    static func tagAccent(seed: Double) -> Color {
        tagPaletteAnchors[tagPaletteIndex(seed: seed)].color
    }
}

struct NotchSpringProfile: Equatable, Sendable {
    let perceptualDuration: TimeInterval
    let bounce: Double

    var animation: Animation {
        .spring(duration: perceptualDuration, bounce: bounce)
    }
}

enum NotchMotion {
    // The shell is intentionally under-damped. Its overshoot gives the large
    // geometry change a soft, elastic edge instead of reading as a staged
    // window resize. Closing uses progressively less energy so it still feels
    // like the opening path being pulled back into the notch.
    static let surfaceExpansion = NotchSpringProfile(perceptualDuration: 0.56, bounce: 0.16)
    static let surfaceContraction = NotchSpringProfile(perceptualDuration: 0.48, bounce: 0.12)
    static let surfaceHide = NotchSpringProfile(perceptualDuration: 0.44, bounce: 0.09)
    static let surfaceContent = NotchSpringProfile(perceptualDuration: 0.38, bounce: 0.07)
    static let contentMorph = NotchSpringProfile(perceptualDuration: 0.30, bounce: 0)
    static let selection = NotchSpringProfile(perceptualDuration: 0.22, bounce: 0)
    static let reorderDisplacement = NotchSpringProfile(perceptualDuration: 0.30, bounce: 0)
    static let dragLift = NotchSpringProfile(perceptualDuration: 0.20, bounce: 0)
    static let dragLanding = NotchSpringProfile(perceptualDuration: 0.34, bounce: 0)
    static let onboardingSpring = NotchSpringProfile(perceptualDuration: 0.28, bounce: 0)
    static let confirmationSpring = NotchSpringProfile(perceptualDuration: 0.32, bounce: 0)
    static let completionSpring = NotchSpringProfile(perceptualDuration: 0.16, bounce: 0)
    // Settings switches use a short, low-bounce thumb spring so their state
    // change feels responsive without competing with the surface motion.
    static let toggleThumb = NotchSpringProfile(perceptualDuration: 0.26, bounce: 0.16)
    // The checkmark is the one deliberately playful element in the completion
    // choreography: a touch of overshoot makes the pop feel earned without the
    // wash or the row itself bouncing.
    static let completionCheckPop = NotchSpringProfile(perceptualDuration: 0.40, bounce: 0.30)

    // Compatibility aliases for policy tests and callers that reason about the
    // perceptual pace without constructing a SwiftUI animation.
    static let surfaceExpansionDuration = surfaceExpansion.perceptualDuration
    static let surfaceContractionDuration = surfaceContraction.perceptualDuration
    static let contentDuration = contentMorph.perceptualDuration
    static let onboardingDuration = onboardingSpring.perceptualDuration
    static let filterDuration = selection.perceptualDuration
    static let controlPressDuration: TimeInterval = 0.12
    static let toggleTrackDuration: TimeInterval = 0.16
    static let hoverDuration: TimeInterval = 0.08
    static let insertionDuration: TimeInterval = 0.18
    static let removalDuration: TimeInterval = 0.14
    static let stagingDelay: TimeInterval = 0.04
    static let surfaceContentDelay: TimeInterval = 0.018
    static let surfaceContentOffset: CGFloat = 6
    static let expandedLedgerDelay: TimeInterval = 0.10
    static let expandedComposerDelay: TimeInterval = 0.24
    static let expandedElementRevealDuration: TimeInterval = 0.24
    static let expandedLedgerOffset: CGFloat = 5
    static let expandedComposerOffset: CGFloat = 8
    static let composerFocusDuration: TimeInterval = 0.18
    static let reducedMotionDuration: TimeInterval = 0.12
    static let completionRevealDuration: TimeInterval = 0.40
    static let completionRetractDuration: TimeInterval = 0.16
    static let completionReopenDuration = completionRetractDuration
    static let completionExitDuration: TimeInterval = 0.22
    // Completion is staged: the check pops, the wash sweeps shortly after, and
    // only once the wash has landed does the row reorder or exit. The hold must
    // outlast washDelay + reveal so the payoff is never cut short.
    static let completionWashDelay: TimeInterval = 0.04
    static let completionHoldDuration: TimeInterval = 0.60
    // The flood peaks when the wash lands, then cools into the resting tint.
    // Cooling starts before the hold releases so settle and cool-down overlap
    // as one continuous exhale rather than two staged beats.
    static let completionCooldownDuration: TimeInterval = 0.30
    static let completionCooldownDelay = completionWashDelay + completionRevealDuration
    static let completionCheckDrawDuration: TimeInterval = 0.28
    static let completionCheckDrawDelay: TimeInterval = 0.06

    static func easeOut(duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    static let content = contentMorph.animation
    static let surfaceContentReveal = surfaceContent.animation
    static let navigation = contentMorph.animation
    static let onboarding = onboardingSpring.animation
    static let confirmation = confirmationSpring.animation
    static let filter = selection.animation
    static let keyboardScroll = selection.animation
    static let controlPress = easeOut(duration: controlPressDuration)
    static let toggleTrack = easeOut(duration: toggleTrackDuration)
    static let hover = easeOut(duration: hoverDuration)
    static let insertion = easeOut(duration: insertionDuration)
    static let removal = easeOut(duration: removalDuration)
    static let dropEnter = selection.animation
    static let dropExit = removal
    static let composerFocus = easeOut(duration: composerFocusDuration)
    static let reducedMotion = easeOut(duration: reducedMotionDuration)
    static let reorder = reorderDisplacement.animation
    static let completion = completionSpring.animation
    static let completionCheck = completionCheckPop.animation
    static let completionSettle = reorderDisplacement.animation
    // Trash/archive/move removals share the reorder spring so the exiting row
    // and the gap closing beneath it always move at the same pace.
    static let ledgerRemoval = reorderDisplacement.animation
    static let completionReopen = easeOut(duration: completionReopenDuration)
    static let completionReveal = easeOut(duration: completionRevealDuration)
    static let completionRetract = easeOut(duration: completionRetractDuration)
    static let completionCooldown = easeOut(duration: completionCooldownDuration)
    static let completionCheckDraw = easeOut(duration: completionCheckDrawDuration)
    static let completionExit = easeOut(duration: completionExitDuration)

    static func landing(initialVelocity: Double) -> Animation {
        .interpolatingSpring(
            duration: dragLanding.perceptualDuration,
            bounce: dragLanding.bounce,
            initialVelocity: min(1, max(-1, initialVelocity))
        )
    }
}

struct NotchHugShape: Shape {
    var bottomRadius: CGFloat = 24

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let flare = min(NotchTheme.topFlare, rect.height / 2, rect.width / 4)
        let radius = min(bottomRadius, rect.height - flare, rect.width / 2 - flare)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare, y: rect.minY + flare),
            control: CGPoint(x: rect.minX + flare, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX + flare, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - flare - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - flare, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX - flare, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - flare, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct NotchSurfaceBackground: View {
    var bottomRadius: CGFloat = 24
    var shadowOpacity: Double = 0.46
    var shadowRadius: CGFloat = 24
    var shadowY: CGFloat = 14

    var body: some View {
        // No backdrop material here: a Material under .shadow compiles to a
        // CABackdropLayer that escapes the shape mask and the surface's layout
        // offset, washing out the desktop as a misplaced rectangle. Behind
        // near-opaque ink it was invisible anyway.
        NotchHugShape(bottomRadius: bottomRadius)
            .fill(NotchTheme.ink.opacity(0.985))
    }
}

extension View {
    /// Keeps a control's entire rendered frame interactive, including transparent padding.
    func notchHitTarget<S: Shape>(_ shape: S) -> some View {
        background(shape.fill(Color.black.opacity(0.001)))
            .contentShape(shape)
    }
}

struct PressableIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var idleForeground: Color = NotchTheme.secondaryText
    var width: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? NotchTheme.primaryText : idleForeground)
            .frame(width: width, height: 28)
            .background(configuration.isPressed ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(NotchTheme.primaryAccent.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct CompactTextButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .notchHitTarget(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct NotchPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct LedgerSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .regular))
            Spacer()
        }
        .foregroundStyle(NotchTheme.secondaryText)
        .padding(.horizontal, 20)
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) items")
    }
}

struct ShortcutKeycap: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.74))
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(Color.white.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
