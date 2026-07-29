import SwiftUI

struct StudioLightPopoverCard: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var coordinator: NotchPresentationCoordinator
    let popover: StudioLightPopover

    private static let size = CGSize(width: 276, height: 196)

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .local)
            let frame = NotchPopoverPlacement.frame(
                anchor: popover.anchor,
                menuSize: Self.size,
                in: bounds
            )
            content
                .frame(width: Self.size.width, height: Self.size.height)
                .background(NotchTheme.raisedGraphite)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NotchTheme.controlStroke)
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: .black.opacity(0.48), radius: 18, y: 9)
                .position(x: frame.midX, y: frame.midY)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Studio light controls")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "laser.burst")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        state.snapshot.isOn && state.controlsEnabled
                            ? NotchTheme.primaryAccent
                            : NotchTheme.secondaryText
                    )
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.05))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.configuredDevice?.name ?? "MOLUS G60")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)
                    Text(state.connection.statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer()

                if state.connection.canRetry && !state.connection.isConnected {
                    Button("Retry") {
                        viewModel.retryStudioLight()
                    }
                    .buttonStyle(StudioLightTextButtonStyle())
                } else {
                    NotchToggle(
                        title: "Studio light power",
                        showsTitle: false,
                        isOn: powerBinding
                    )
                    .disabled(!state.controlsEnabled)
                }
            }

            StudioLightSliderRow(
                title: "Brightness",
                valueText: "\(Int(state.snapshot.brightness.rounded()))%",
                value: brightnessBinding,
                range: 0...100,
                step: 1
            ) { editing in
                if !editing {
                    viewModel.setStudioLightBrightness(
                        state.snapshot.brightness,
                        final: true
                    )
                }
            }
            .disabled(!state.controlsEnabled)

            StudioLightSliderRow(
                title: "Temperature",
                valueText: "\(state.snapshot.colorTemperature) K",
                value: temperatureBinding,
                range: 2_700...6_500,
                step: 100
            ) { editing in
                if !editing {
                    viewModel.setStudioLightColorTemperature(
                        state.snapshot.colorTemperature,
                        final: true
                    )
                }
            }
            .disabled(!state.controlsEnabled)

            if !state.controlsEnabled {
                Text("Keep the fixture powered and disconnect it from ZY Vega.")
                    .font(.system(size: 8.8))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(13)
    }

    private var state: StudioLightViewState {
        viewModel.studioLightState
    }

    private var statusColor: Color {
        switch state.connection {
        case .connected:
            NotchTheme.secondaryText
        case .connecting, .scanning:
            NotchTheme.primaryAccent
        default:
            NotchTheme.destructive.opacity(0.88)
        }
    }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { state.snapshot.isOn },
            set: { viewModel.setStudioLightPower($0) }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { state.snapshot.brightness },
            set: { viewModel.setStudioLightBrightness($0, final: false) }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { Double(state.snapshot.colorTemperature) },
            set: {
                viewModel.setStudioLightColorTemperature(
                    Int($0.rounded()),
                    final: false
                )
            }
        )
    }
}

private struct StudioLightSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
                Spacer()
                Text(valueText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchTheme.primaryText)
                    .monospacedDigit()
            }
            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: onEditingChanged
            )
            .controlSize(.mini)
            .tint(NotchTheme.primaryAccent)
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
        }
        .opacity(value.isFinite ? 1 : 0.55)
    }
}

private struct StudioLightTextButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
                configuration.isPressed
                    ? NotchTheme.primaryAccent
                    : NotchTheme.primaryText
            )
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .notchHitTarget(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : NotchMotion.controlPress,
                value: configuration.isPressed
            )
    }
}
