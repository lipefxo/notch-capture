import SwiftUI

enum NotchTheme {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 560
    static let headerHeight: CGFloat = 70
    static let mint = Color(red: 0.43, green: 0.91, blue: 0.74)
    static let ink = Color(red: 0.025, green: 0.028, blue: 0.032)
    static let graphite = Color(red: 0.095, green: 0.101, blue: 0.11)
    static let raisedGraphite = Color(red: 0.135, green: 0.143, blue: 0.155)
    static let hairline = Color.white.opacity(0.085)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)
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
            .fill(NotchTheme.ink.opacity(0.96))
            .background(.ultraThinMaterial, in: NotchHugShape(bottomRadius: 24))
            .overlay {
                NotchHugShape(bottomRadius: 24)
                    .stroke(NotchTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
    }
}

struct PressableIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(configuration.isPressed ? Color.white.opacity(0.13) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MintButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(NotchTheme.mint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LedgerSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
        }
        .foregroundStyle(NotchTheme.tertiaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) items")
    }
}

struct ShortcutKeycap: View {
    let value: String

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .medium, design: .rounded))
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
