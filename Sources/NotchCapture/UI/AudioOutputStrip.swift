import SwiftUI

struct AudioOutputSegmentPresentation: Equatable {
    let target: AudioOutputTarget
    let isAvailable: Bool
    let isSelected: Bool

    var accessibilityValue: String {
        if isSelected { return "Selected" }
        return isAvailable ? "Available" : "Unavailable"
    }

    static func make(
        target: AudioOutputTarget,
        state: AudioOutputViewState
    ) -> Self {
        Self(
            target: target,
            isAvailable: state.isAvailable(target),
            isSelected: state.isSelected(target)
        )
    }
}

struct AudioOutputStrip: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AudioOutputTarget.allCases.enumerated()), id: \.element.id) { index, target in
                if index > 0 {
                    Rectangle()
                        .fill(NotchTheme.hairline)
                        .frame(width: 1, height: 24)
                        .accessibilityHidden(true)
                }
                segment(for: target)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(NotchTheme.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio output")
        .accessibilityValue(viewModel.audioOutputState.accessibilityCurrentOutput)
    }

    private func segment(for target: AudioOutputTarget) -> some View {
        let presentation = AudioOutputSegmentPresentation.make(
            target: target,
            state: viewModel.audioOutputState
        )
        let color = foreground(for: presentation)
        return Button {
            viewModel.selectAudioOutput(target)
        } label: {
            ZStack(alignment: .bottom) {
                HStack(spacing: 7) {
                    deviceIcon(
                        target,
                        isAvailable: presentation.isAvailable,
                        color: color
                    )
                    AudioOutputCanvasLabel(
                        text: target.displayName,
                        width: labelWidth(for: target),
                        color: color
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if presentation.isSelected {
                    Rectangle()
                        .fill(NotchTheme.dueAccent)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.98, pressedOpacity: 0.78))
        .disabled(!presentation.isAvailable)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(target.displayName)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(
            presentation.isAvailable && !presentation.isSelected
                ? "Switch all Mac audio to \(target.displayName)"
                : ""
        )
        .accessibilityAddTraits(presentation.isSelected ? .isSelected : [])
    }

    private func deviceIcon(
        _ target: AudioOutputTarget,
        isAvailable: Bool,
        color: Color
    ) -> some View {
        Image(systemName: target.symbolName)
            .renderingMode(.template)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: target == .edifier ? 12.5 : 13, weight: .medium))
            .foregroundColor(color)
            .frame(width: 18, height: 18)
            .overlay(alignment: .bottomTrailing) {
                if !isAvailable {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            NotchTheme.tertiaryText.opacity(0.75),
                            NotchTheme.ink
                        )
                        .offset(x: 3, y: 2)
                }
            }
            .accessibilityHidden(true)
    }

    private func labelWidth(for target: AudioOutputTarget) -> CGFloat {
        switch target {
        case .airPods: 42
        case .edifier: 38
        case .headphones: 64
        }
    }

    private func foreground(
        for presentation: AudioOutputSegmentPresentation
    ) -> Color {
        if presentation.isSelected { return NotchTheme.dueAccent }
        if presentation.isAvailable { return NotchTheme.secondaryText }
        return NotchTheme.tertiaryText.opacity(0.45)
    }
}

private struct AudioOutputCanvasLabel: View {
    let text: String
    let width: CGFloat
    let color: Color

    var body: some View {
        // The persistent AppKit host can omit later static glyph runs in a new
        // row on its first commit. Resolving each compact label into the
        // SwiftUI canvas keeps all three device names reliably visible.
        Canvas { context, size in
            let label = context.resolve(
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(color)
            )
            context.draw(
                label,
                at: CGPoint(x: 0, y: size.height / 2),
                anchor: .leading
            )
        }
        .frame(width: width, height: 16)
        .accessibilityHidden(true)
    }
}
