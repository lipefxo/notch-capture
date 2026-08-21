import AppKit
import SwiftUI

struct CollapsedActivityPillView: View {
    @ObservedObject var viewModel: AppViewModel
    let presentationSize: CompactPresentationSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExtended: Bool { presentationSize == .extended }

    private var compactMetrics: CompactSurfaceMetrics {
        CompactSurfaceMetrics.resolve(
            state: .collapsedActivity,
            presentationSize: presentationSize,
            activityLayout: viewModel.collapsedActivityLayout
        )!
    }

    var body: some View {
        Group {
            if viewModel.collapsedActivityLayout.hasHardwareNotch {
                if isExtended {
                    notchedLayout
                } else {
                    minimalNotchedLayout
                }
            } else {
                fallbackLayout
            }
        }
        .animation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content, value: viewModel.isNowPlayingRecovering)
        .accessibilityElement(children: .contain)
    }

    /// Minimal full-screen presentation hugs the physical notch while keeping
    /// the active music controls and mirror toggle inside the compact shell.
    private var minimalNotchedLayout: some View {
        HStack(spacing: 4) {
            notchedMusicWing
            compactMirrorToggle
        }
            .frame(
                width: compactMetrics.contentSize.width,
                height: compactMetrics.contentSize.height
            )
    }

    private var notchedLayout: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                notchedMusicWing
            }
                .frame(
                    width: compactMetrics.wingWidth ?? NotchTheme.collapsedActivityWingWidth,
                    height: compactMetrics.contentSize.height
                )
            Color.clear
                .frame(width: max(0, viewModel.collapsedActivityLayout.notchWidth))
                .allowsHitTesting(false)
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                notchedTrailingWing
            }
                .frame(
                    width: compactMetrics.wingWidth ?? NotchTheme.collapsedActivityWingWidth,
                    height: compactMetrics.contentSize.height
                )
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
                compactMirrorToggle
            }
            .padding(.horizontal, 12)
            .frame(width: compactMetrics.contentSize.width, height: 34)
        case nil:
            EmptyView()
        }
    }

    private var compactMirrorToggle: some View {
        MirrorToggleButton(
            viewModel: viewModel,
            glyphSize: 11,
            width: CompactSurfaceMetrics.mirrorToggleSlot - 6
        )
    }

    @ViewBuilder
    private var extendedFallbackLayout: some View {
        switch viewModel.collapsedActivityContent {
        case let .musicOnly(snapshot):
            HStack(spacing: 8) {
                extendedMusicInfoView(snapshot)
                    .frame(maxWidth: .infinity)
                extendedMirrorToggle
            }
            .padding(.horizontal, 12)
            .frame(width: compactMetrics.contentSize.width, height: compactMetrics.contentSize.height)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var notchedMusicWing: some View {
        if let snapshot = viewModel.nowPlaying {
            HStack(spacing: 6) {
                ArtworkPlaybackControl(
                    artwork: viewModel.nowPlayingArtwork,
                    trackKey: snapshot.trackKey,
                    title: snapshot.title,
                    isPlaying: snapshot.isPlaying,
                    size: 22,
                    cornerRadius: 5,
                    action: viewModel.musicPlayPause
                )
                .allowsHitTesting(!viewModel.isNowPlayingRecovering)
                .accessibilityHidden(viewModel.isNowPlayingRecovering)
                .opacity(viewModel.isNowPlayingRecovering ? 0.55 : 1)

                CollapsedTransportControls(viewModel: viewModel, snapshot: snapshot)
                    .frame(width: 52)
            }
            .frame(height: compactMetrics.contentSize.height)
        }
    }

    private var extendedMirrorToggle: some View {
        MirrorToggleButton(
            viewModel: viewModel,
            glyphSize: 13,
            width: CompactSurfaceMetrics.mirrorToggleSlot
        )
    }

    private var notchedTrailingWing: some View {
        extendedMirrorToggle
            .frame(height: compactMetrics.contentSize.height)
    }

    private func musicInfoView(
        _ snapshot: NowPlayingSnapshot,
        artworkSize: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            if viewModel.isNowPlayingRecovering {
                trackText(snapshot)
                    .frame(maxWidth: .infinity, maxHeight: 34, alignment: .leading)
            } else {
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

    @ViewBuilder
    private func extendedMusicInfoView(_ snapshot: NowPlayingSnapshot) -> some View {
        if viewModel.isNowPlayingRecovering {
            HStack(spacing: 8) {
                trackText(snapshot)
                CollapsedRetryButton(viewModel: viewModel, source: snapshot.source)
            }
        } else {
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
    }

    private func musicAccessibilityLabel(_ snapshot: NowPlayingSnapshot) -> String {
        "Open \(snapshot.title) by \(snapshot.artist)"
    }
}

/// Matches the opened player's control placement: transport lives beside the
/// metadata, directly above the read-only progress strip.
private struct ExtendedInlineTransportControls: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        if viewModel.isNowPlayingRecovering, let source = viewModel.nowPlaying?.source {
            CollapsedRetryButton(viewModel: viewModel, source: source)
        } else {
            HStack(spacing: 14) {
                control("backward.fill", label: "Previous track", action: viewModel.musicPrevious)
                control("forward.fill", label: "Next track", action: viewModel.musicNext)
            }
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
        if viewModel.isNowPlayingRecovering {
            CollapsedRetryButton(viewModel: viewModel, source: snapshot.source)
        } else {
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

private struct CollapsedRetryButton: View {
    @ObservedObject var viewModel: AppViewModel
    let source: NowPlayingSource

    var body: some View {
        Button { viewModel.reconnectMedia(source) } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 25)
        }
        .buttonStyle(PressableIconButtonStyle(width: 25))
        .notchHitTarget(Circle())
        .help("Retry \(source.applicationName) connection")
        .accessibilityLabel("Retry \(source.applicationName) connection")
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
