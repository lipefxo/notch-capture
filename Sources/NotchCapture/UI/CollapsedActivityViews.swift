import AppKit
import SwiftUI

struct CollapsedActivityPillView: View {
    @ObservedObject var viewModel: AppViewModel

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
                .frame(width: NotchTheme.collapsedActivityWingWidth, alignment: .leading)
            Color.clear
                .frame(width: max(0, viewModel.collapsedActivityLayout.notchWidth))
            trailingWing
                .frame(width: NotchTheme.collapsedActivityWingWidth, alignment: .trailing)
        }
        .frame(height: max(34, viewModel.collapsedActivityLayout.notchBandHeight + 4), alignment: .top)
    }

    @ViewBuilder
    private var fallbackLayout: some View {
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
            Button { viewModel.openExpanded() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "timer")
                        .foregroundStyle(NotchTheme.mint)
                    PomodoroCountdownLabel(state: state)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.94))
            .frame(width: 280, height: 34)
            .accessibilityLabel("Open focus timer")
        case let .both(snapshot, state):
            HStack(spacing: 6) {
                musicInfoView(snapshot, artworkSize: 22)
                    .frame(maxWidth: .infinity)
                CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                    .frame(width: 42)
                PomodoroCountdownLabel(state: state)
                    .frame(width: 42)
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 34)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var leadingWing: some View {
        if let snapshot = viewModel.nowPlaying {
            musicInfoView(snapshot, artworkSize: 22)
                .padding(.leading, 2)
                .frame(maxHeight: 34)
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        if let snapshot = viewModel.nowPlaying {
            HStack(spacing: viewModel.pomodoro.isActive ? 6 : 0) {
                CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                    .frame(width: viewModel.pomodoro.isActive ? 42 : nil)
                if viewModel.pomodoro.isActive {
                    PomodoroCountdownLabel(state: viewModel.pomodoro)
                        .frame(width: 42)
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: 34)
        } else if viewModel.pomodoro.isActive {
            Button { viewModel.openExpanded() } label: {
                PomodoroCountdownLabel(state: viewModel.pomodoro)
                    .frame(maxWidth: .infinity, maxHeight: 34)
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.94))
            .accessibilityLabel("Open focus timer")
        }
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

    private func musicAccessibilityLabel(_ snapshot: NowPlayingSnapshot) -> String {
        "Open \(snapshot.title) by \(snapshot.artist)"
    }
}

private struct CollapsedTransportControls: View {
    @ObservedObject var viewModel: AppViewModel
    let snapshot: NowPlayingSnapshot

    var body: some View {
        HStack(spacing: 2) {
            control("chevron.left", label: "Previous track") {
                viewModel.musicPrevious()
            }
            control("chevron.right", label: "Next track") {
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
            Text(Self.format(state.remaining(at: context.date)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(NotchTheme.mint)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
