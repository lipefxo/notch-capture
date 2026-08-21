import SwiftUI

enum AudioVolumePresentation {
    static func symbolName(for state: AudioVolumeViewState) -> String {
        guard !state.isEffectivelyMuted else { return "speaker.slash.fill" }
        switch state.clampedValue ?? 0 {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// Entry point shared by idle and now-playing compact surfaces. It opens a
/// focused notch surface instead of placing a cramped slider in the pill.
struct CompactVolumeButton: View {
    @ObservedObject var viewModel: AppViewModel
    var glyphSize: CGFloat = 12
    var width: CGFloat = CompactSurfaceMetrics.audioControlSlot

    private var volume: AudioVolumeViewState {
        viewModel.audioOutputState.volume
    }

    var body: some View {
        Button(action: viewModel.openVolumeControl) {
            Image(systemName: AudioVolumePresentation.symbolName(for: volume))
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: glyphSize, weight: .regular))
        }
        .buttonStyle(PressableIconButtonStyle(width: width))
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("Open volume controls")
        .accessibilityLabel("Open volume controls")
        .accessibilityValue(volume.accessibilityValue)
        .accessibilityHint("Shows system output volume in the notch")
    }
}

struct VolumeControlSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        AudioVolumeControlRow(
            viewModel: viewModel,
            height: 56,
            showsBackButton: true
        )
        .background(NotchTheme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Output volume controls")
    }
}

struct AudioVolumeControlRow: View {
    @ObservedObject var viewModel: AppViewModel
    let height: CGFloat
    var showsBackButton = false

    private var state: AudioVolumeViewState {
        viewModel.audioOutputState.volume
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { state.clampedValue ?? 0 },
            set: { viewModel.setOutputVolume($0) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.setOutputMuted(!state.isMuted)
            } label: {
                AudioVolumeSpeakerGlyph(symbolName: AudioVolumePresentation.symbolName(for: state))
            }
            .buttonStyle(PressableIconButtonStyle(width: 28))
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .disabled(!state.canSetMute)
            .help(state.canSetMute ? (state.isMuted ? "Unmute output" : "Mute output") : "Use device controls")
            .accessibilityLabel(state.isMuted ? "Unmute output" : "Mute output")
            .accessibilityValue(state.accessibilityValue)

            Slider(value: sliderBinding, in: 0...1)
                .controlSize(.mini)
                .tint(NotchTheme.primaryText)
                .disabled(!state.canSetVolume)
                .accessibilityLabel("Output volume")
                .accessibilityValue(state.accessibilityValue)
                .accessibilityHint(state.canSetVolume ? "Adjusts the current Mac output" : "Use controls on the output device")

            AudioVolumeCanvasValue(text: state.percentageText)
                .frame(width: state.clampedValue == nil ? 92 : 34)

            if showsBackButton {
                Button(action: viewModel.closeVolumeControl) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PressableIconButtonStyle(width: 28))
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("Back to compact notch")
                .accessibilityLabel("Close volume controls")
            }
        }
        .padding(.horizontal, showsBackButton ? 12 : 20)
        .frame(height: height)
        .background(NotchTheme.ink)
    }
}

private struct AudioVolumeSpeakerGlyph: View {
    let symbolName: String

    var body: some View {
        Canvas { context, size in
            var symbol = context.resolve(Image(systemName: symbolName))
            symbol.shading = .color(NotchTheme.secondaryText)
            let fittedSize = CGSize(
                width: min(size.width, symbol.size.width),
                height: min(size.height, symbol.size.height)
            )
            context.draw(
                symbol,
                in: CGRect(
                    x: (size.width - fittedSize.width) / 2,
                    y: (size.height - fittedSize.height) / 2,
                    width: fittedSize.width,
                    height: fittedSize.height
                )
            )
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct AudioVolumeCanvasValue: View {
    let text: String

    var body: some View {
        Canvas { context, size in
            let label = context.resolve(
                Text(text)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchTheme.secondaryText)
            )
            context.draw(
                label,
                at: CGPoint(x: size.width, y: size.height / 2),
                anchor: .trailing
            )
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
