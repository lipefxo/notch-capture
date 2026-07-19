import SwiftUI

struct UtilityShelfView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        if let snapshot = viewModel.nowPlaying {
            MusicPlayerBand(viewModel: viewModel, snapshot: snapshot)
                .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }
}

private struct MusicPlayerBand: View {
    @ObservedObject var viewModel: AppViewModel
    let snapshot: NowPlayingSnapshot

    var body: some View {
        HStack(spacing: 11) {
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.primaryText)
                    Text(snapshot.artist)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                .lineLimit(1)

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

            HStack(spacing: 2) {
                transportButton("chevron.left", label: "Previous track", action: viewModel.musicPrevious, compact: true)
                transportButton("chevron.right", label: "Next track", action: viewModel.musicNext, compact: true)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(NotchTheme.graphite)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(playerAccessibilityLabel)
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
        .buttonStyle(PressableIconButtonStyle())
        .notchHitTarget(Circle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var playerAccessibilityLabel: String {
        let base = "Now playing \(snapshot.title) by \(snapshot.artist)"
        guard let duration = MusicTimeFormatter.durationString(from: snapshot.duration) else {
            return base
        }
        return "\(base), duration \(duration)"
    }
}

private struct MusicDurationLabel: View {
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

private struct MusicProgressControl: View {
    let snapshot: NowPlayingSnapshot
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubFraction: Double?
    @State private var isHovered = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 : 1 / 30,
                paused: !snapshot.isPlaying
            )
        ) { context in
            let fraction = scrubFraction ?? snapshot.progress(at: context.date)
            let displayedPosition = snapshot.position(at: context.date, previewing: scrubFraction)

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
        let fillWidth = width * fraction
        let thumbX = min(max(3.5, fillWidth), max(3.5, width - 3.5))

        return ZStack(alignment: .leading) {
            Color.black.opacity(0.001)

            Capsule()
                .fill(Color.white.opacity(0.09))
                .frame(height: 3)

            Capsule()
                .fill(NotchTheme.mint.opacity(0.9))
                .frame(width: fillWidth, height: 3)

            Circle()
                .fill(NotchTheme.mint)
                .frame(width: 7, height: 7)
                .position(x: thumbX, y: 7)
                .opacity(isHovered || scrubFraction != nil ? 1 : 0)
                .scaleEffect(isHovered || scrubFraction != nil ? 1 : 0.7)
                .animation(reduceMotion ? nil : NotchMotion.hover, value: isHovered)
        }
        .frame(width: width, height: 14)
        .contentShape(Rectangle())
        .gesture(seekGesture(width: width))
        .onHover { isHovered = $0 }
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard snapshot.duration > 0, width > 0 else { return }
                scrubFraction = min(1, max(0, value.location.x / width))
            }
            .onEnded { value in
                guard snapshot.duration > 0, width > 0 else {
                    scrubFraction = nil
                    return
                }
                let fraction = min(1, max(0, value.location.x / width))
                scrubFraction = nil
                onSeek(snapshot.duration * fraction)
            }
    }

    private var accessibilityValue: String {
        guard let total = MusicTimeFormatter.durationString(from: snapshot.duration) else {
            return "Unavailable"
        }
        let current = MusicTimeFormatter.string(from: snapshot.position(at: .now))
        return "\(current) of \(total)"
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
