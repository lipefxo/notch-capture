import Foundation
import SwiftUI

struct OnboardingFeaturePage<Illustration: View>: View {
    let headline: String
    let subtitle: String
    @ViewBuilder let illustration: () -> Illustration

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            illustration()

            VStack(spacing: 7) {
                Text(headline)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 30)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 28)
    }
}

struct OnboardingCapturePage: View {
    var body: some View {
        OnboardingFeaturePage(
            headline: "Capture your thoughts",
            subtitle: "Use the composer bar to add or search"
        ) {
            OnboardingComposerIllustration()
        }
    }
}

struct OnboardingOrganizePage: View {
    var body: some View {
        OnboardingFeaturePage(
            headline: "Tidy up your notes",
            subtitle: "Use folders and tags to organize your captures"
        ) {
            OnboardingOrganizeIllustration()
        }
    }
}

struct OnboardingMusicPage: View {
    var body: some View {
        OnboardingFeaturePage(
            headline: "Keep the tunes going",
            subtitle: "Control your songs from Spotify or Apple Music"
        ) {
            OnboardingMusicIllustration()
        }
    }
}

private struct OnboardingLoopTimeline<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let duration: TimeInterval
    let staticPhase: Double
    @ViewBuilder let content: (Double, TimeInterval) -> Content

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 20,
                paused: reduceMotion
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion
                ? staticPhase
                : time.truncatingRemainder(dividingBy: duration) / duration

            content(phase, reduceMotion ? 0 : time)
        }
    }
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let progress = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return progress * progress * (3 - (2 * progress))
}

private struct OnboardingMockCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NotchTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OnboardingComposerIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: TimeInterval = 5.6
    private let captureText = "Buy oat milk @errands"
    private let placeholder = "Search, add an item, or / to see actions"

    var body: some View {
        OnboardingLoopTimeline(duration: duration, staticPhase: 3.4 / duration) { phase, time in
            let elapsed = phase * duration
            let displayText = displayedText(at: elapsed)
            let usesPlaceholder = elapsed < 0.6
            let showsCaret = !reduceMotion && caretIsVisible(at: elapsed, time: time)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NotchTheme.secondaryText)

                HStack(spacing: 1.5) {
                    Text(displayText)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            usesPlaceholder ? NotchTheme.tertiaryText : NotchTheme.primaryText
                        )
                        .lineLimit(1)

                    if showsCaret {
                        Rectangle()
                            .fill(NotchTheme.primaryText)
                            .frame(width: 1.5, height: 16)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: 340)
            .frame(height: 48)
            .background(NotchTheme.field)
            .clipShape(
                RoundedRectangle(cornerRadius: NotchTheme.surfaceBottomRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NotchTheme.surfaceBottomRadius, style: .continuous)
                    .strokeBorder(NotchTheme.controlStroke, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Composer example typing Buy oat milk tagged errands into the capture field."
        )
    }

    private func displayedText(at elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<0.6:
            placeholder
        case ..<2.7:
            String(captureText.prefix(min(captureText.count, Int((elapsed - 0.6) / 0.1))))
        case ..<4.8:
            captureText
        default:
            ""
        }
    }

    private func caretIsVisible(at elapsed: TimeInterval, time: TimeInterval) -> Bool {
        switch elapsed {
        case ..<0.6:
            time.truncatingRemainder(dividingBy: 1) < 0.5
        case ..<2.7:
            true
        case ..<4.8:
            time.truncatingRemainder(dividingBy: 1) < 0.5
        default:
            false
        }
    }
}

private struct OnboardingOrganizeIllustration: View {
    private let duration: TimeInterval = 6
    private let tags = [
        (name: "research", count: 3, colorSeed: 0.12),
        (name: "reading", count: 5, colorSeed: 0.48),
        (name: "later", count: 2, colorSeed: 0.82),
    ]

    var body: some View {
        OnboardingLoopTimeline(duration: duration, staticPhase: 0) { phase, _ in
            let elapsed = phase * duration
            let count = elapsed >= 4.7 ? 5 : 4
            let rowPulse = smoothstep(4.55, 4.7, elapsed)
                * (1 - smoothstep(4.7, 5, elapsed))

            OnboardingMockCard {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NotchTheme.secondaryText)
                        Text("Reading list")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryText)
                        Spacer(minLength: 8)
                        Text("\(count) items")
                            .font(.system(size: 9.5))
                            .foregroundStyle(NotchTheme.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.03 * rowPulse))

                    Rectangle().fill(NotchTheme.hairline).frame(height: 1)

                    HStack(spacing: 10) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                            let emphasis = chipEmphasis(index: index, elapsed: elapsed)

                            TonalTagLabel(
                                name: tag.name,
                                count: tag.count,
                                colorSeed: tag.colorSeed
                            )
                            .opacity(0.55 + (0.45 * emphasis))
                            .scaleEffect(CGFloat(0.97 + (0.03 * emphasis)))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Organization example with a Reading list folder and research, reading, and later tags."
        )
    }

    private func chipEmphasis(index: Int, elapsed: TimeInterval) -> Double {
        let start = 0.6 + (Double(index) * 1.3)
        let rampIn = smoothstep(start, start + 0.22, elapsed)
        let rampOut = 1 - smoothstep(start + 0.85, start + 1.1, elapsed)
        return min(rampIn, rampOut)
    }
}

private struct OnboardingMusicIllustration: View {
    private let duration: TimeInterval = 8

    var body: some View {
        OnboardingLoopTimeline(duration: duration, staticPhase: 0.36) { phase, time in
            OnboardingMockCard {
                VStack(spacing: 13) {
                    HStack(spacing: 11) {
                        HStack(alignment: .center, spacing: 2.5) {
                            ForEach(0..<4, id: \.self) { index in
                                let wave = (sin((time * 3.2) + (Double(index) * 1.7)) + 1) / 2

                                Capsule()
                                    .fill(NotchTheme.primaryAccent)
                                    .frame(width: 3, height: CGFloat(6 + (12 * wave)))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(NotchTheme.control)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Currents")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(NotchTheme.primaryText)
                            Text("Tame Impala")
                                .font(.system(size: 9.5))
                                .foregroundStyle(NotchTheme.tertiaryText)
                        }

                        Spacer(minLength: 0)
                    }

                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(NotchTheme.primaryAccent)
                                    .frame(
                                        width: proxy.size.width * CGFloat(0.15 + (0.70 * phase))
                                    )
                            }
                        }

                    HStack(spacing: 20) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                }
                .padding(14)
                .frame(width: 250)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Music playback example for Currents by Tame Impala with progress and transport controls."
        )
    }
}
