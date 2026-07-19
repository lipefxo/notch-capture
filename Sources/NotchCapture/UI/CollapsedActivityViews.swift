import AppKit
import SwiftUI

struct CollapsedActivityPillView: View {
    @ObservedObject var viewModel: AppViewModel

    private var isExtended: Bool { viewModel.compactPresentationSize == .extended }

    private var compactMetrics: CompactSurfaceMetrics {
        CompactSurfaceMetrics.resolve(
            state: .collapsedActivity,
            presentationSize: viewModel.compactPresentationSize,
            activityLayout: viewModel.collapsedActivityLayout
        )!
    }

    var body: some View {
        Group {
            if viewModel.collapsedActivityLayout.hasHardwareNotch {
                notchedLayout
            } else {
                fallbackLayout
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var notchedLayout: some View {
        HStack(spacing: 0) {
            leadingWing
                .frame(width: compactMetrics.wingWidth ?? NotchTheme.collapsedActivityWingWidth, alignment: .leading)
            Color.clear
                .frame(width: max(0, viewModel.collapsedActivityLayout.notchWidth))
            trailingWing
                .frame(width: compactMetrics.wingWidth ?? NotchTheme.collapsedActivityWingWidth, alignment: .trailing)
        }
        .frame(height: compactMetrics.contentSize.height, alignment: .top)
    }

    @ViewBuilder
    private var fallbackLayout: some View {
        if isExtended {
            extendedFallbackLayout
        } else {
            minimalFallbackLayout
        }
    }

    @ViewBuilder
    private var minimalFallbackLayout: some View {
        switch viewModel.collapsedActivityContent {
        case let .musicOnly(snapshot):
            HStack(spacing: 6) {
                musicInfoView(snapshot, artworkSize: 22)
                    .frame(maxWidth: .infinity)
                CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                    .frame(width: 52)
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 34)
        case let .pomodoroOnly(state):
            CompactPomodoroButton(viewModel: viewModel, state: state)
                .frame(width: 280, height: 34)
        case let .both(snapshot, state):
            HStack(spacing: 6) {
                musicInfoView(snapshot, artworkSize: 22)
                    .frame(maxWidth: .infinity)
                CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                    .frame(width: 42)
                compactPomodoroButton(state)
                    .frame(width: 54)
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 34)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var extendedFallbackLayout: some View {
        switch viewModel.collapsedActivityContent {
        case let .musicOnly(snapshot):
            extendedMusicInfoView(snapshot)
            .padding(.horizontal, 12)
            .frame(width: compactMetrics.contentSize.width, height: compactMetrics.contentSize.height)
        case let .pomodoroOnly(state):
            ExtendedCompactPomodoroButton(viewModel: viewModel, state: state)
                .frame(width: compactMetrics.contentSize.width, height: compactMetrics.contentSize.height)
        case let .both(snapshot, state):
            HStack(spacing: 8) {
                extendedMusicInfoView(snapshot)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                ExtendedCompactPomodoroButton(viewModel: viewModel, state: state)
                    .frame(width: 72, height: compactMetrics.contentSize.height)
                    .layoutPriority(2)
            }
            .padding(.horizontal, 12)
            .frame(width: compactMetrics.contentSize.width, height: compactMetrics.contentSize.height)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var leadingWing: some View {
        if let snapshot = viewModel.nowPlaying {
            Group {
                if isExtended {
                    extendedMusicInfoView(snapshot)
                } else {
                    musicInfoView(snapshot, artworkSize: 22)
                }
            }
            .padding(.leading, 2)
            .frame(maxHeight: compactMetrics.contentSize.height)
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        if let snapshot = viewModel.nowPlaying {
            if isExtended {
                if viewModel.pomodoro.isActive {
                    ExtendedCompactPomodoroButton(viewModel: viewModel, state: viewModel.pomodoro)
                        .frame(width: 86)
                }
            } else {
                HStack(spacing: viewModel.pomodoro.isActive ? 6 : 0) {
                    CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                        .frame(width: viewModel.pomodoro.isActive ? 42 : nil)
                    if viewModel.pomodoro.isActive {
                        compactPomodoroButton(viewModel.pomodoro)
                            .frame(width: 54)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, maxHeight: compactMetrics.contentSize.height)
            }
        } else if viewModel.pomodoro.isActive {
            Group {
                if isExtended {
                    ExtendedCompactPomodoroButton(viewModel: viewModel, state: viewModel.pomodoro)
                } else {
                    CompactPomodoroButton(viewModel: viewModel, state: viewModel.pomodoro)
                }
            }
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, maxHeight: compactMetrics.contentSize.height, alignment: .trailing)
        }
    }

    private func compactPomodoroButton(_ state: PomodoroState) -> some View {
        CompactPomodoroButton(viewModel: viewModel, state: state)
    }

    private func musicInfoView(
        _ snapshot: NowPlayingSnapshot,
        artworkSize: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            ArtworkPlaybackControl(
                artwork: viewModel.nowPlayingArtwork,
                trackKey: snapshot.trackKey,
                title: snapshot.title,
                isPlaying: snapshot.isPlaying,
                size: artworkSize,
                cornerRadius: 5,
                action: viewModel.musicPlayPause
            )

            Button { viewModel.openExpanded() } label: {
                trackText(snapshot)
                    .frame(maxWidth: .infinity, maxHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.94))
            .help("Open \(snapshot.title) in Notch Capture")
            .accessibilityLabel(musicAccessibilityLabel(snapshot))
        }
    }

    private func trackText(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
            Text(snapshot.artist)
                .font(.system(size: 8.5))
                .foregroundStyle(NotchTheme.secondaryText)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private func extendedMusicInfoView(_ snapshot: NowPlayingSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ArtworkPlaybackControl(
                    artwork: viewModel.nowPlayingArtwork,
                    trackKey: snapshot.trackKey,
                    title: snapshot.title,
                    isPlaying: snapshot.isPlaying,
                    size: 38,
                    cornerRadius: 8,
                    action: viewModel.musicPlayPause
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Button { viewModel.openExpanded() } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(snapshot.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(NotchTheme.primaryText)
                                Text(snapshot.artist)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(NotchTheme.secondaryText)
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.94))
                        .help("Open \(snapshot.title) in Notch Capture")
                        .accessibilityLabel(musicAccessibilityLabel(snapshot))
                        .layoutPriority(1)

                        ExtendedInlineTransportControls(viewModel: viewModel)
                            .layoutPriority(2)
                    }

                    if let duration = MusicTimeFormatter.durationString(from: snapshot.duration) {
                        HStack(spacing: 4) {
                            MusicProgressControl(
                                snapshot: snapshot,
                                onSeek: viewModel.musicSeek
                            )
                            .frame(minWidth: 0, maxWidth: .infinity)

                            MusicDurationLabel(duration: duration)
                        }
                        .frame(height: 14)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
    }

    private func musicAccessibilityLabel(_ snapshot: NowPlayingSnapshot) -> String {
        "Open \(snapshot.title) by \(snapshot.artist)"
    }
}

private struct CompactPomodoroButton: View {
    @ObservedObject var viewModel: AppViewModel
    let state: PomodoroState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isHovered
            || isFocused
            || CommandLine.arguments.contains("--preview-pomodoro-hover")
            || CommandLine.arguments.contains("--preview-pomodoro-focus")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = state.remaining(at: context.date)
            Button(action: viewModel.togglePomodoro) {
                PomodoroCountdownText(
                    state: state,
                    remaining: remaining,
                    emphasized: isHighlighted
                )
            }
            .buttonStyle(CompactPomodoroButtonStyle(
                isHighlighted: isHighlighted,
                isPreviewPressed: CommandLine.arguments.contains("--preview-pomodoro-pressed"),
                reduceMotion: reduceMotion
            ))
            .focused($isFocused)
            .focusEffectDisabled()
            .onHover { isHovered = $0 }
            .help(actionLabel)
            .accessibilityLabel(actionLabel)
            .accessibilityValue(PomodoroCountdownLabel.accessibilityValue(remaining))
        }
    }

    private var actionLabel: String {
        switch state.phase {
        case .idle: "Start focus timer"
        case .running: "Pause focus timer"
        case .paused: "Resume focus timer"
        case .finished: "Restart focus timer"
        }
    }
}

/// Extended Pomodoro deliberately remains a single, plain timer. The larger
/// full-surface hit target preserves the compact timer's existing action.
private struct ExtendedCompactPomodoroButton: View {
    @ObservedObject var viewModel: AppViewModel
    let state: PomodoroState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = state.remaining(at: context.date)
            Button(action: viewModel.togglePomodoro) {
                Text(PomodoroCountdownLabel.format(remaining))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(foregroundColor(remaining))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.9))
            .notchHitTarget(Rectangle())
            .help(actionLabel)
            .accessibilityLabel(actionLabel)
            .accessibilityValue(PomodoroCountdownLabel.accessibilityValue(remaining))
        }
    }

    private var actionLabel: String {
        switch state.phase {
        case .idle: "Start focus timer"
        case .running: "Pause focus timer"
        case .paused: "Resume focus timer"
        case .finished: "Restart focus timer"
        }
    }

    private func foregroundColor(_ remaining: TimeInterval) -> Color {
        if case .paused = state.phase { return NotchTheme.secondaryText }
        return NotchTheme.pomodoroTimerColor(remaining: remaining, duration: state.duration).color
    }
}

private struct CompactPomodoroButtonStyle: ButtonStyle {
    let isHighlighted: Bool
    let isPreviewPressed: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || isPreviewPressed
        configuration.label
            .frame(width: 54, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: isPressed))
            )
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.hover, value: isHighlighted)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed { return Color.white.opacity(0.10) }
        return isHighlighted ? NotchTheme.control : .clear
    }
}

/// Matches the opened player's control placement: transport lives beside the
/// metadata, directly above the read-only progress strip.
private struct ExtendedInlineTransportControls: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            control("backward.fill", label: "Previous track", action: viewModel.musicPrevious)
            control("forward.fill", label: "Next track", action: viewModel.musicNext)
        }
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 16, height: 25)
        }
        .buttonStyle(PressableIconButtonStyle(width: 16))
        .notchHitTarget(Circle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CollapsedTransportControls: View {
    @ObservedObject var viewModel: AppViewModel
    let snapshot: NowPlayingSnapshot

    var body: some View {
        HStack(spacing: 2) {
            control("backward.fill", label: "Previous track") {
                viewModel.musicPrevious()
            }
            control("forward.fill", label: "Next track") {
                viewModel.musicNext()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(CollapsedTransportButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CollapsedTransportButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(configuration.isPressed ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

struct PomodoroCountdownLabel: View {
    let state: PomodoroState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = state.remaining(at: context.date)
            PomodoroCountdownText(state: state, remaining: remaining)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func accessibilityValue(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        let minutes = value / 60
        let seconds = value % 60
        let minuteUnit = minutes == 1 ? "minute" : "minutes"
        let secondUnit = seconds == 1 ? "second" : "seconds"
        return "\(minutes) \(minuteUnit), \(seconds) \(secondUnit) remaining"
    }
}

private struct PomodoroCountdownText: View {
    let state: PomodoroState
    let remaining: TimeInterval
    var emphasized = false

    var body: some View {
        Text(PomodoroCountdownLabel.format(remaining))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
            .brightness(emphasized ? 0.08 : 0)
    }

    private var foregroundColor: Color {
        if case .paused = state.phase {
            return NotchTheme.secondaryText
        }
        return NotchTheme.pomodoroTimerColor(
            remaining: remaining,
            duration: state.duration
        ).color
    }
}
