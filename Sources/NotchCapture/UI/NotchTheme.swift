import SwiftUI

enum NotchTheme {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 560
    static let headerHeight: CGFloat = 62
    static let mint = Color(red: 0.23, green: 0.78, blue: 0.50)
    static let ink = Color(red: 0.022, green: 0.024, blue: 0.027)
    static let graphite = Color(red: 0.070, green: 0.074, blue: 0.080)
    static let raisedGraphite = Color(red: 0.110, green: 0.114, blue: 0.122)
    static let field = Color(red: 0.065, green: 0.067, blue: 0.072)
    static let control = Color.white.opacity(0.060)
    static let selectedControl = Color.white.opacity(0.135)
    static let selectedLedger = Color.white.opacity(0.055)
    static let hoveredLedger = Color.white.opacity(0.028)
    static let controlStroke = Color.white.opacity(0.075)
    static let hairline = Color.white.opacity(0.065)
    static let primaryText = Color.white.opacity(0.90)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.39)
    static let dueAccent = Color(red: 0.48, green: 0.49, blue: 0.86)
    static let composerIridescence = Gradient(colors: [
        Color(red: 0.31, green: 0.89, blue: 1.00),
        Color(red: 0.46, green: 0.42, blue: 1.00),
        Color(red: 0.93, green: 0.34, blue: 0.94),
        Color(red: 1.00, green: 0.42, blue: 0.55),
        Color(red: 1.00, green: 0.78, blue: 0.30),
        Color(red: 0.28, green: 0.94, blue: 0.65),
        Color(red: 0.31, green: 0.89, blue: 1.00),
    ])
}

enum NotchMotion {
    static let surfaceExpansionDuration: TimeInterval = 0.22
    static let surfaceContractionDuration: TimeInterval = 0.16
    static let contentDuration: TimeInterval = 0.16
    static let onboardingDuration: TimeInterval = 0.20
    static let filterDuration: TimeInterval = 0.15
    static let controlPressDuration: TimeInterval = 0.12
    static let hoverDuration: TimeInterval = 0.08
    static let dropEnterDuration: TimeInterval = 0.14
    static let dropExitDuration: TimeInterval = 0.10
    static let composerFocusDuration: TimeInterval = 0.18
    static let composerIridescenceCycleDuration: TimeInterval = 10
    static let reducedMotionDuration: TimeInterval = 0.10

    static func easeOut(duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    static let content = easeOut(duration: contentDuration)
    static let onboarding = easeOut(duration: onboardingDuration)
    static let filter = easeOut(duration: filterDuration)
    static let controlPress = easeOut(duration: controlPressDuration)
    static let hover = easeOut(duration: hoverDuration)
    static let dropEnter = easeOut(duration: dropEnterDuration)
    static let dropExit = easeOut(duration: dropExitDuration)
    static let composerFocus = easeOut(duration: composerFocusDuration)
    static let reducedMotion = easeOut(duration: reducedMotionDuration)
    static let reorder = Animation.spring(response: 0.32, dampingFraction: 1, blendDuration: 0)
}

struct NotchHugShape: Shape {
    var bottomRadius: CGFloat = 24
    var topLift: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let topY = rect.minY + topLift
        let topRadius = min(16, rect.width / 8)
        let tabHalfWidth = min(17, rect.width / 10)
        let centerX = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: topY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: topY),
            control: CGPoint(x: rect.minX, y: topY)
        )
        path.addLine(to: CGPoint(x: centerX - tabHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: centerX + tabHalfWidth, y: topY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: topY + topRadius),
            control: CGPoint(x: rect.maxX, y: topY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct NotchSurfaceBackground: View {
    var body: some View {
        NotchHugShape(bottomRadius: 24)
            .fill(NotchTheme.ink.opacity(0.985))
            .background(.ultraThinMaterial, in: NotchHugShape(bottomRadius: 24))
            .overlay {
                NotchHugShape(bottomRadius: 24)
                    .stroke(NotchTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.46), radius: 24, y: 14)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .frame(width: 28, height: 28)
            .background(configuration.isPressed ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct MintButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(NotchTheme.mint.opacity(configuration.isPressed ? 0.78 : 1))
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
