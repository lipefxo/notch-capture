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
            artwork

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.primaryText)
                    Text(snapshot.artist)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                .lineLimit(1)

                MusicProgressControl(snapshot: snapshot, onSeek: viewModel.musicSeek)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                transportButton("backward.fill", label: "Previous track", action: viewModel.musicPrevious)
                transportButton(snapshot.isPlaying ? "pause.fill" : "play.fill", label: snapshot.isPlaying ? "Pause" : "Play", action: viewModel.musicPlayPause)
                transportButton("forward.fill", label: "Next track", action: viewModel.musicNext)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(NotchTheme.graphite)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(snapshot.title) by \(snapshot.artist)")
    }

    private var artwork: some View {
        Group {
            if let image = viewModel.nowPlayingArtwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.055))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func transportButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 25, height: 25)
        }
        .buttonStyle(PressableIconButtonStyle())
        .notchHitTarget(Circle())
        .help(label)
        .accessibilityLabel(label)
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
            GeometryReader { proxy in
                let fraction = scrubFraction ?? snapshot.progress(at: context.date)
                let width = max(0, proxy.size.width)
                let fillWidth = width * fraction
                let thumbX = min(max(3.5, fillWidth), max(3.5, width - 3.5))

                ZStack(alignment: .leading) {
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
                        .position(x: thumbX, y: proxy.size.height / 2)
                        .opacity(isHovered || scrubFraction != nil ? 1 : 0)
                        .scaleEffect(isHovered || scrubFraction != nil ? 1 : 0.7)
                        .animation(reduceMotion ? nil : NotchMotion.hover, value: isHovered)
                }
                .contentShape(Rectangle())
                .gesture(seekGesture(width: width))
            }
        }
        .frame(height: 14)
        .allowsHitTesting(snapshot.duration > 0)
        .onHover { isHovered = $0 }
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
        let current = Self.format(snapshot.position(at: .now))
        let total = Self.format(snapshot.duration)
        return "\(current) of \(total)"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
