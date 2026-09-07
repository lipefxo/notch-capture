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
        return min(1, max(0, date.timeIntervalSince(settleStartedAt) / 0.78))
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
        GeometryReader { proxy in
            let phaseOffset: CGFloat = provider == .openAI ? 0 : .pi * 0.62
            let progress = CGFloat(min(1, max(0, settleProgress)))
            let energy = reduceMotion ? 0 : pow(1 - progress, 2)
            let phase = phaseOffset + (progress * .pi * 2.15)
            let amplitude = 0.48 + (energy * 1.12)
            let normalizedLevel = CGFloat(min(1, max(0, level)))

            ZStack {
                ProviderLogo(provider: provider)
                    .foregroundStyle(NotchTheme.primaryText.opacity(ghostOpacity))

                LiquidLevelShape(
                    level: normalizedLevel,
                    phase: phase,
                    amplitude: amplitude
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.68),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask {
                    ProviderLogo(provider: provider)
                }

                if normalizedLevel > 0.02 && normalizedLevel < 0.98 {
                    LiquidSurfaceShape(
                        level: normalizedLevel,
                        phase: phase,
                        amplitude: amplitude
                    )
                    .stroke(Color.white.opacity(0.52), lineWidth: 0.72)
                    .shadow(color: Color.white.opacity(0.20), radius: 0.8, y: -0.35)
                    .mask {
                        ProviderLogo(provider: provider)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .drawingGroup(opaque: false, colorMode: .linear)
        .accessibilityHidden(true)
    }
}

private struct LiquidLevelShape: Shape {
    var level: CGFloat
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard level > 0.001 else { return Path() }
        guard level < 0.999 else { return Path(rect) }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: surfacePoint(index: 0, samples: 24, in: rect))

        for index in 1...24 {
            path.addLine(to: surfacePoint(index: index, samples: 24, in: rect))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    fileprivate func surfacePoint(index: Int, samples: Int, in rect: CGRect) -> CGPoint {
        let progress = CGFloat(index) / CGFloat(samples)
        let baseY = rect.minY + ((1 - min(1, max(0, level))) * rect.height)
        let edgeDamping = min(1, level * 8, (1 - level) * 8)
        let wave = sin((progress * .pi * 2) + phase) * amplitude * edgeDamping
        return CGPoint(
            x: rect.minX + (progress * rect.width),
            y: min(rect.maxY, max(rect.minY, baseY + wave))
        )
    }
}

private struct LiquidSurfaceShape: Shape {
    var level: CGFloat
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let levelShape = LiquidLevelShape(level: level, phase: phase, amplitude: amplitude)
        var path = Path()
        path.move(to: levelShape.surfacePoint(index: 0, samples: 24, in: rect))
        for index in 1...24 {
            path.addLine(to: levelShape.surfacePoint(index: index, samples: 24, in: rect))
        }
        return path
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

    private static func image(named name: String) -> NSImage? {
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
