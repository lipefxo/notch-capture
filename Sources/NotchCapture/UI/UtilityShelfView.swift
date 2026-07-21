import SwiftUI

struct UtilityShelfView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let presentation = viewModel.nowPlayingPresentation {
            MusicPlayerBand(viewModel: viewModel, presentation: presentation)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                .animation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content, value: presentation.state)
        }
    }
}

private struct MusicPlayerBand: View {
    @ObservedObject var viewModel: AppViewModel
    let presentation: NowPlayingPresentation

    private var snapshot: NowPlayingSnapshot { presentation.snapshot }

    var body: some View {
        HStack(spacing: 11) {
            if presentation.isRecovery {
                recoveryContent
            } else {
                liveContent
            }
        }
        // Match the header, folder rows, and ledger rows so the player does
        // not hang outside the shared expanded-surface content column.
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(playerAccessibilityLabel)
    }

    private var liveContent: some View {
        Group {
            ArtworkPlaybackControl(
                artwork: viewModel.nowPlayingArtwork,
                trackKey: snapshot.trackKey,
                title: snapshot.title,
                isPlaying: snapshot.isPlaying,
                size: 40,
                cornerRadius: 8,
                action: viewModel.musicPlayPause
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.primaryText)
                        Text(snapshot.artist)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 14) {
                        transportButton("backward.fill", label: "Previous track", action: viewModel.musicPrevious, compact: true)
                        transportButton("forward.fill", label: "Next track", action: viewModel.musicNext, compact: true)
                    }
                }

                HStack(spacing: 6) {
                    MusicProgressControl(snapshot: snapshot, onSeek: viewModel.musicSeek)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    if let duration = MusicTimeFormatter.durationString(from: snapshot.duration) {
                        MusicDurationLabel(duration: duration)
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recoveryContent: some View {
        Group {
            Image(systemName: presentation.state == .permissionDenied ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(presentation.state == .permissionDenied ? NotchTheme.secondaryText : NotchTheme.destructive)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                Text("\(presentation.state.statusText) · \(snapshot.artist)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if presentation.state.requiresSystemSettings {
                Button("System Settings", action: viewModel.openMediaAutomationSettings)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryAccent)
                    .buttonStyle(.plain)
            }
            if presentation.state.requiresAppRestart {
                Button("Quit", action: viewModel.hooks.onQuit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryAccent)
                    .buttonStyle(.plain)
                    .help("Quit and reopen Notch Capture")
                    .accessibilityLabel("Quit and reopen Notch Capture")
            } else if presentation.state.canReconnect {
                Button {
                    viewModel.reconnectMedia(presentation.source)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(PressableIconButtonStyle(width: 28))
                .notchHitTarget(Circle())
                .help("Retry \(presentation.source.applicationName) connection")
                .accessibilityLabel("Retry \(presentation.source.applicationName) connection")
            }
        }
    }

    private func transportButton(
        _ icon: String,
        label: String,
        action: @escaping () -> Void,
        compact: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: compact ? 16 : 25, height: 25)
        }
        .buttonStyle(PressableIconButtonStyle(width: compact ? 16 : 28))
        .notchHitTarget(Circle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var playerAccessibilityLabel: String {
        let base = presentation.isRecovery
            ? "\(presentation.state.statusText), \(snapshot.title) by \(snapshot.artist)"
            : "Now playing \(snapshot.title) by \(snapshot.artist)"
        guard let duration = MusicTimeFormatter.durationString(from: snapshot.duration) else {
            return base
        }
        return "\(base), duration \(duration)"
    }
}

struct MusicDurationLabel: View {
    let duration: String

    var body: some View {
        // The persistent AppKit host can drop the final static glyph run on its
        // first commit. Resolving this tiny label into the existing SwiftUI
        // canvas keeps the total visible without adding a timer or repaint loop.
        Canvas { context, size in
            let label = context.resolve(
                Text(duration)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchTheme.secondaryText)
            )
            context.draw(
                label,
                at: CGPoint(x: size.width, y: size.height / 2),
                anchor: .trailing
            )
        }
        .frame(width: duration.count > 5 ? 40 : 28, height: 12)
        .layoutPriority(2)
        .accessibilityHidden(true)
    }
}

enum MusicScrubGeometry {
    static func fraction(at xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, xPosition / width))
    }

    static func thumbCenter(
        fraction: Double,
        width: CGFloat,
        diameter: CGFloat
    ) -> CGFloat {
        guard width > 0 else { return 0 }
        let radius = min(width / 2, max(0, diameter / 2))
        let rawPosition = width * CGFloat(min(1, max(0, fraction)))
        return min(max(radius, rawPosition), width - radius)
    }

    static func committedFraction(
        previewing previewFraction: Double?,
        releaseX: CGFloat,
        width: CGFloat
    ) -> Double {
        // SwiftUI can report the gesture's initial local location on mouse-up
        // after the track redraws during a drag. The continuously updated
        // preview is therefore the authoritative release position.
        previewFraction ?? fraction(at: releaseX, width: width)
    }
}

struct MusicProgressControl: View {
    let snapshot: NowPlayingSnapshot
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scrubFraction: Double?
    @State private var isHovered = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 : 1 / 30,
                paused: !snapshot.isPlaying
            )
        ) { context in
            let previewFraction = scrubFraction ?? forcedPreviewScrubFraction
            let fraction = previewFraction ?? snapshot.progress(at: context.date)
            let displayedPosition = snapshot.position(at: context.date, previewing: previewFraction)

            HStack(spacing: 6) {
                if let total = MusicTimeFormatter.durationString(from: snapshot.duration) {
                    let labelWidth: CGFloat = total.count > 5 ? 40 : 28
                    timeLabel(
                        MusicTimeFormatter.string(from: displayedPosition),
                        width: labelWidth,
                        alignment: .leading
                    )

                    GeometryReader { proxy in
                        seekTrack(width: max(0, proxy.size.width), fraction: fraction)
                    }
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 3)
                }
            }
        }
        .frame(height: 14)
        .allowsHitTesting(snapshot.duration > 0)
        .onChange(of: snapshot.trackKey) { _, _ in
            scrubFraction = nil
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard snapshot.duration > 0 else { return }
            let current = snapshot.position(at: .now)
            switch direction {
            case .increment:
                onSeek(min(snapshot.duration, current + 10))
            case .decrement:
                onSeek(max(0, current - 10))
            @unknown default:
                break
            }
        }
    }

    private func seekTrack(width: CGFloat, fraction: Double) -> some View {
        let clampedFraction = min(1, max(0, fraction))
        let fillWidth = width * clampedFraction
        let showsThumb = isHovered || scrubFraction != nil || forcedPreviewScrubFraction != nil

        return ZStack(alignment: .leading) {
            Color.black.opacity(0.001)

            Capsule()
                .fill(Color.white.opacity(0.09))
                .frame(height: 3)

            if #available(macOS 26.0, *), !reduceTransparency {
                LiquidGlassMusicProgressTrack(
                    trackWidth: width,
                    fillWidth: fillWidth,
                    thumbX: MusicScrubGeometry.thumbCenter(
                        fraction: clampedFraction,
                        width: width,
                        diameter: 9
                    ),
                    showsThumb: showsThumb,
                    reduceMotion: reduceMotion
                )
            } else {
                legacyProgressTrack(
                    trackWidth: width,
                    fillWidth: fillWidth,
                    thumbX: MusicScrubGeometry.thumbCenter(
                        fraction: clampedFraction,
                        width: width,
                        diameter: 7
                    ),
                    showsThumb: showsThumb
                )
            }
        }
        .frame(width: width, height: 14)
        .contentShape(Rectangle())
        .gesture(seekGesture(width: width))
        .onHover { isHovered = $0 }
    }

    private func legacyProgressTrack(
        trackWidth: CGFloat,
        fillWidth: CGFloat,
        thumbX: CGFloat,
        showsThumb: Bool
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(NotchTheme.primaryAccent.opacity(0.9))
                .frame(width: fillWidth, height: 3)

            Circle()
                .fill(NotchTheme.primaryAccent)
                .frame(width: 7, height: 7)
                .position(x: thumbX, y: 7)
                .opacity(showsThumb ? 1 : 0)
                .scaleEffect(showsThumb ? 1 : 0.7)
                .animation(reduceMotion ? nil : NotchMotion.hover, value: showsThumb)
        }
        .frame(width: trackWidth, height: 14, alignment: .leading)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard snapshot.duration > 0, width > 0 else { return }
                scrubFraction = MusicScrubGeometry.fraction(
                    at: value.location.x,
                    width: width
                )
            }
            .onEnded { value in
                guard snapshot.duration > 0, width > 0 else {
                    scrubFraction = nil
                    return
                }
                let fraction = MusicScrubGeometry.committedFraction(
                    previewing: scrubFraction,
                    releaseX: value.location.x,
                    width: width
                )
                onSeek(snapshot.duration * fraction)
                scrubFraction = nil
            }
    }

    private var accessibilityValue: String {
        guard let total = MusicTimeFormatter.durationString(from: snapshot.duration) else {
            return "Unavailable"
        }
        let current = MusicTimeFormatter.string(from: snapshot.position(at: .now))
        return "\(current) of \(total)"
    }

    private var forcedPreviewScrubFraction: Double? {
#if DEBUG
        guard let argument = CommandLine.arguments.first(where: {
            $0.hasPrefix("--preview-music-scrub=")
        }) else {
            return nil
        }
        let value = String(argument.dropFirst("--preview-music-scrub=".count))
        return Double(value).map { min(1, max(0, $0)) }
#else
        return nil
#endif
    }

    private func timeLabel(
        _ value: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(value)
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(NotchTheme.secondaryText)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .layoutPriority(1)
            .accessibilityHidden(true)
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassMusicProgressTrack: View {
    let trackWidth: CGFloat
    let fillWidth: CGFloat
    let thumbX: CGFloat
    let showsThumb: Bool
    let reduceMotion: Bool

    var body: some View {
        GlassEffectContainer(spacing: 2) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NotchTheme.primaryAccent.opacity(0.38))
                    .frame(width: fillWidth, height: 4)
                    .glassEffect(glass, in: Capsule())

                if showsThumb {
                    Circle()
                        .fill(NotchTheme.primaryAccent.opacity(0.42))
                        .frame(width: 9, height: 9)
                        .glassEffect(glass, in: Circle())
                        .glassEffectTransition(reduceMotion ? .identity : .materialize)
                        .position(x: thumbX, y: 7)
                }
            }
            .frame(width: trackWidth, height: 14, alignment: .leading)
        }
        .animation(reduceMotion ? nil : NotchMotion.hover, value: showsThumb)
    }

    private var glass: Glass {
        .regular
            .tint(NotchTheme.primaryAccent.opacity(0.55))
            .interactive()
    }
}
