import SwiftUI
import AppKit

struct ModelUsageSettingsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SettingsGroup(title: "Model Usage", subtitle: "OpenAI and Cursor") {
            ForEach(Array(ModelUsageProvider.allCases.enumerated()), id: \.element) { index, provider in
                ModelUsageProviderRow(
                    provider: provider,
                    state: viewModel.modelUsageState[provider],
                    showsMeter: true,
                    onRefresh: { viewModel.refreshModelUsage() }
                )

                if index < ModelUsageProvider.allCases.count - 1 {
                    SettingsDivider(leadingInset: 44)
                }
            }

            SettingsDivider()
            Text(
                "Remaining usage is read from the ChatGPT and Cursor accounts already signed in on this Mac. Tokens stay in those apps; Notch Capture only asks for the current allowance."
            )
            .font(.system(size: 9))
            .foregroundStyle(NotchTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

struct ModelUsageProviderRow: View {
    let provider: ModelUsageProvider
    let state: ModelUsageProviderState
    var showsMeter: Bool
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ModelUsageSettingsLogo(provider: provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.primaryText)
                    Text(statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 27, height: 27)
                } else {
                    Button("Refresh", action: onRefresh)
                        .buttonStyle(SettingsButtonStyle())
                }
            }

            if showsMeter, let fraction = state.connection.snapshot?.remainingFraction {
                ModelUsageMeterBar(fraction: fraction)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName), \(statusText)")
    }

    private var statusText: String {
        if case .notSignedIn = state.connection {
            return provider.signInHint
        }
        if let snapshot = state.connection.snapshot {
            return snapshot.statusText
        }
        return state.statusText
    }

    private var statusColor: Color {
        switch state.connection {
        case .failed:
            NotchTheme.destructive.opacity(0.88)
        case .notSignedIn:
            NotchTheme.secondaryText
        case let .loaded(snapshot):
            ModelUsageMeterBar.color(forRemainingFraction: snapshot.remainingFraction)
        case .loading:
            NotchTheme.primaryAccent
        }
    }
}

struct ModelUsageLogoStrip: View {
    let state: ModelUsageViewState
    var logoSize: CGFloat = 19
    var spacing: CGFloat = 11

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(ModelUsageProvider.allCases) { provider in
                ModelUsageLogoMeter(
                    provider: provider,
                    state: state[provider],
                    size: logoSize
                )
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

struct ModelUsageLogoMeter: View {
    private enum Motion {
        static let settleDuration: TimeInterval = 0.78
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let provider: ModelUsageProvider
    let state: ModelUsageProviderState
    var size: CGFloat = 19

    @State private var isSettling = false
    @State private var settleStartedAt = Date.distantPast
    @State private var isHovered = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion || !isSettling
            )
        ) { context in
            LiquidProviderLogo(
                provider: provider,
                level: fillLevel,
                ghostOpacity: ModelUsageLogoFill.ghostOpacity(for: state),
                settleProgress: settleProgress(at: context.date),
                reduceMotion: reduceMotion
            )
        }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .spring(duration: 0.52, bounce: 0.10), value: fillLevel)
            .animation(NotchMotion.content, value: state.isBusy)
            .onChange(of: fillLevel) { oldValue, newValue in
                guard !reduceMotion, oldValue != newValue else { return }
                settleStartedAt = .now
                isSettling = true
            }
            .task(id: settleStartedAt) {
                guard isSettling else { return }
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                isSettling = false
            }
            .onHover { isHovered = $0 }
            .popover(
                isPresented: $isHovered,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ModelUsageHoverCard(
                    provider: provider,
                    statusText: hoverStatusText
                )
            }
            .accessibilityElement()
            .accessibilityLabel(provider.displayName)
            .accessibilityValue(accessibilityValue)
    }

    private var fillLevel: Double {
        ModelUsageLogoFill.level(for: state)
    }

    private func settleProgress(at date: Date) -> Double {
        guard isSettling, !reduceMotion else { return 1 }
        return min(1, max(0, date.timeIntervalSince(settleStartedAt) / Motion.settleDuration))
    }

    private var hoverStatusText: String {
        if let snapshot = state.connection.snapshot,
           let fraction = snapshot.remainingFraction {
            return "\(ModelUsageFormatting.formattedPercent(fraction * 100))% left"
        }
        return state.statusText
    }

    private var accessibilityValue: String {
        if let snapshot = state.connection.snapshot,
           let fraction = snapshot.remainingFraction {
            return "\(ModelUsageFormatting.formattedPercent(fraction * 100)) percent remaining"
        }
        return state.statusText
    }
}

private struct ModelUsageHoverCard: View {
    let provider: ModelUsageProvider
    let statusText: String

    var body: some View {
        HStack(spacing: 7) {
            ProviderLogo(provider: provider)
                .foregroundStyle(NotchTheme.primaryText)
                .frame(width: 13, height: 13)
            Text("\(provider.displayName) · \(statusText)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .presentationBackground(NotchTheme.raisedGraphite)
        .accessibilityElement(children: .combine)
    }
}

enum ModelUsageLogoFill {
    static let inactiveOpacity = 0.18

    static func level(for state: ModelUsageProviderState) -> Double {
        guard let fraction = state.connection.snapshot?.remainingFraction else { return 0 }
        return min(1, max(0, fraction))
    }

    static func ghostOpacity(for state: ModelUsageProviderState) -> Double {
        state.isBusy ? 0.34 : inactiveOpacity
    }
}

private struct LiquidProviderLogo: View {
    let provider: ModelUsageProvider
    let level: Double
    let ghostOpacity: Double
    let settleProgress: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            ProviderLogo(provider: provider)
                .foregroundStyle(NotchTheme.primaryText.opacity(ghostOpacity))

            ContinuousLiquidProviderFill(
                provider: provider,
                level: level,
                settleProgress: settleProgress,
                reduceMotion: reduceMotion
            )
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

private struct ContinuousLiquidProviderFill: NSViewRepresentable {
    let provider: ModelUsageProvider
    let level: Double
    let settleProgress: Double
    let reduceMotion: Bool

    func makeNSView(context: Context) -> LiquidProviderFillView {
        LiquidProviderFillView()
    }

    func updateNSView(_ view: LiquidProviderFillView, context: Context) {
        let progress = CGFloat(min(1, max(0, settleProgress)))
        let energy = reduceMotion ? 0 : pow(1 - progress, 2)
        view.update(
            provider: provider,
            level: CGFloat(min(1, max(0, level))),
            phase: (provider == .openAI ? 0 : .pi * 0.62) + (progress * .pi * 2.15),
            amplitude: 0.48 + (energy * 1.12),
            reduceMotion: reduceMotion
        )
    }
}

enum LiquidWaveGeometry {
    static func paths(
        in rect: CGRect,
        level: CGFloat,
        phase: CGFloat,
        amplitude: CGFloat,
        samples: Int = 24
    ) -> (fill: CGPath, surface: CGPath) {
        let surfacePoints = (0...samples).map { index -> CGPoint in
            let progress = CGFloat(index) / CGFloat(samples)
            let baseY = min(1, max(0, level)) * rect.height
            let edgeDamping = min(1, level * 8, (1 - level) * 8)
            let wave = sin((progress * .pi * 2) + phase) * amplitude * edgeDamping
            return CGPoint(
                x: progress * rect.width,
                y: min(rect.maxY, max(rect.minY, baseY + wave))
            )
        }

        let fillPath = CGMutablePath()
        fillPath.move(to: .zero)
        fillPath.addLine(to: surfacePoints[0])
        for point in surfacePoints.dropFirst() {
            fillPath.addLine(to: point)
        }
        fillPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        fillPath.closeSubpath()

        let surfacePath = CGMutablePath()
        surfacePath.move(to: surfacePoints[0])
        for point in surfacePoints.dropFirst() {
            surfacePath.addLine(to: point)
        }
        return (fillPath, surfacePath)
    }
}

private final class LiquidProviderFillView: NSView {
    private static let fillAnimationKey = "continuousLiquidFill"
    private static let surfaceAnimationKey = "continuousLiquidSurface"
    private static let cycleDuration: TimeInterval = 4.8

    private let maskedLayer = CALayer()
    private let logoMaskLayer = CALayer()
    private let liquidLayer = CAShapeLayer()
    private let surfaceLayer = CAShapeLayer()

    private var provider = ModelUsageProvider.openAI
    private var level: CGFloat = 0
    private var phase: CGFloat = 0
    private var amplitude: CGFloat = 0.48
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        maskedLayer.masksToBounds = true
        maskedLayer.mask = logoMaskLayer
        layer?.addSublayer(maskedLayer)

        liquidLayer.fillColor = NSColor.white.withAlphaComponent(0.88).cgColor
        maskedLayer.addSublayer(liquidLayer)

        surfaceLayer.fillColor = nil
        surfaceLayer.strokeColor = NSColor.white.withAlphaComponent(0.52).cgColor
        surfaceLayer.lineWidth = 0.72
        surfaceLayer.lineJoin = .round
        surfaceLayer.shadowColor = NSColor.white.withAlphaComponent(0.20).cgColor
        surfaceLayer.shadowOpacity = 1
        surfaceLayer.shadowRadius = 0.8
        surfaceLayer.shadowOffset = CGSize(width: 0, height: 0.35)
        maskedLayer.addSublayer(surfaceLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        provider: ModelUsageProvider,
        level: CGFloat,
        phase: CGFloat,
        amplitude: CGFloat,
        reduceMotion: Bool
    ) {
        let changed = self.provider != provider
            || abs(self.level - level) > 0.0001
            || abs(self.phase - phase) > 0.0001
            || abs(self.amplitude - amplitude) > 0.0001
            || self.reduceMotion != reduceMotion
        guard changed else { return }

        self.provider = provider
        self.level = level
        self.phase = phase
        self.amplitude = amplitude
        self.reduceMotion = reduceMotion
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskedLayer.frame = bounds
        logoMaskLayer.frame = bounds
        liquidLayer.frame = bounds
        surfaceLayer.frame = bounds
        updateLogoMask()
        updateWavePaths(in: bounds)
        CATransaction.commit()
    }

    private func updateLogoMask() {
        var proposedRect = bounds
        let image = ProviderLogo.image(named: provider.logoResourceName)
        logoMaskLayer.contents = image?.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
        logoMaskLayer.contentsGravity = .resizeAspect
        logoMaskLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func updateWavePaths(in rect: CGRect) {
        liquidLayer.removeAnimation(forKey: Self.fillAnimationKey)
        surfaceLayer.removeAnimation(forKey: Self.surfaceAnimationKey)

        guard level > 0.001 else {
            liquidLayer.path = nil
            surfaceLayer.path = nil
            return
        }
        guard level < 0.999 else {
            liquidLayer.path = CGPath(rect: rect, transform: nil)
            surfaceLayer.path = nil
            return
        }

        let frameCount = 72
        let phases = (0..<frameCount).map { frame in
            phase + ((CGFloat(frame) / CGFloat(frameCount)) * .pi * 2)
        }
        let paths = phases.map {
            LiquidWaveGeometry.paths(
                in: rect,
                level: level,
                phase: $0,
                amplitude: amplitude
            )
        }
        liquidLayer.path = paths[0].fill
        surfaceLayer.path = paths[0].surface

        guard !reduceMotion,
              level > 0.02,
              level < 0.98 else { return }

        let keyTimes = (0..<frameCount).map { frame in
            NSNumber(value: Double(frame) / Double(frameCount))
        }
        let fillAnimation = CAKeyframeAnimation(keyPath: "path")
        fillAnimation.values = paths.map(\.fill)
        fillAnimation.keyTimes = keyTimes
        fillAnimation.duration = Self.cycleDuration
        fillAnimation.repeatCount = .infinity
        fillAnimation.calculationMode = .discrete
        fillAnimation.isRemovedOnCompletion = false
        liquidLayer.add(fillAnimation, forKey: Self.fillAnimationKey)

        let surfaceAnimation = CAKeyframeAnimation(keyPath: "path")
        surfaceAnimation.values = paths.map(\.surface)
        surfaceAnimation.keyTimes = keyTimes
        surfaceAnimation.duration = Self.cycleDuration
        surfaceAnimation.repeatCount = .infinity
        surfaceAnimation.calculationMode = .discrete
        surfaceAnimation.isRemovedOnCompletion = false
        surfaceLayer.add(surfaceAnimation, forKey: Self.surfaceAnimationKey)
    }

}

private struct ProviderLogo: View {
    let provider: ModelUsageProvider

    var body: some View {
        Group {
            if let image = Self.image(named: provider.logoResourceName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: provider.symbolName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }

    fileprivate static func image(named name: String) -> NSImage? {
        let installedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("NotchCapture_NotchCapture.bundle") }
            .flatMap(Bundle.init(url:))
        let resources = installedBundle ?? Bundle.module
        guard let url = resources.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct ModelUsageSettingsLogo: View {
    let provider: ModelUsageProvider

    var body: some View {
        ProviderLogo(provider: provider)
            .foregroundStyle(NotchTheme.secondaryText)
            .frame(width: 14, height: 14)
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ModelUsageMeterBar: View {
    var fraction: Double
    var remainingFraction: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Self.color(forRemainingFraction: remainingFraction).opacity(0.85))
                    .frame(width: max(4, proxy.size.width * remainingFraction))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    static func color(forRemainingFraction fraction: Double?) -> Color {
        guard let fraction else { return NotchTheme.secondaryText }
        if fraction <= 0.05 {
            return NotchTheme.destructive.opacity(0.88)
        }
        if fraction <= 0.20 {
            return NotchTheme.warning
        }
        return NotchTheme.secondaryText
    }
}
