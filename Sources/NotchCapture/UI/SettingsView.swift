import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var presentation: NotchPresentationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        generalSection
                        mediaSection
                        studioLightSection
                        shortcutsSection
                        privacyAndDataSection
                            .id("privacy-and-data")
                        quitAction
                            .id("settings-end")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                }
                .onAppear {
                    guard CommandLine.arguments.contains("--preview-settings-bottom") else { return }
                    proxy.scrollTo("settings-end", anchor: .bottom)
                }
            }
            .background(NotchTheme.graphite)
        }
        .frame(width: NotchTheme.width, height: NotchTheme.maxHeight)
        .onExitCommand { viewModel.openExpanded() }
        .onChange(of: viewModel.shortcutRecordingRequest) { _, request in
            guard let request else { return }
            presentShortcutRecorder(request)
        }
        .onDisappear {
            viewModel.hooks.onCancelShortcutRecording()
            viewModel.cancelStudioLightPairing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture settings")
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.openExpanded()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PressableIconButtonStyle())
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back to inbox")

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var generalSection: some View {
        SettingsGroup(title: "General") {
            SettingsToggleRow(
                title: "Launch at login",
                detail: "Keep capture shortcuts ready after you sign in",
                isOn: $viewModel.launchAtLogin
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Hide pill on external displays",
                detail: "Shortcuts still open Notch Capture",
                isOn: $viewModel.autoHideExternalPill
            )
            SettingsDivider()
            SettingsControlRow(title: "Compact size", detail: "Minimal or Extended") {
                NotchSegmentedControl(
                    options: CompactPresentationSize.allCases,
                    selection: $viewModel.compactPresentationSize
                )
                .frame(width: 164)
                .accessibilityLabel("Compact size")
            }
            SettingsDivider()
            SettingsControlRow(title: "Time format", detail: "Capture timestamps") {
                NotchSegmentedControl(
                    options: AppViewModel.TimeFormat.allCases,
                    selection: $viewModel.timeFormat
                )
                .frame(width: 142)
                .accessibilityLabel("Time format")
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsGroup(title: "Shortcuts", subtitle: "Available from every app") {
            ForEach(Array(viewModel.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                Button {
                    viewModel.hooks.onOpenShortcutRecorder(shortcut.action)
                } label: {
                    HStack(spacing: 10) {
                        SettingsRowIcon(symbol: "square.and.pencil")
                        Text(shortcut.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryText)
                        Spacer()
                        ShortcutKeycap(value: shortcut.displayValue)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .notchHitTarget(Rectangle())
                }
                .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.82))
                .notchHitTarget(Rectangle())
                .accessibilityLabel("\(shortcut.title), \(shortcut.displayValue)")
                .accessibilityHint("Change this shortcut")

                if index < viewModel.shortcuts.count - 1 {
                    SettingsDivider(leadingInset: 44)
                }
            }
        }
    }

    private var mediaSection: some View {
        SettingsGroup(title: "Media", subtitle: "Playback connections") {
            ForEach(Array(NowPlayingSource.allCases.enumerated()), id: \.element.rawValue) { index, source in
                let state = viewModel.mediaConnectionState(for: source)
                HStack(spacing: 8) {
                    SettingsRowIcon(symbol: source == .appleMusic ? "music.note" : "waveform")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.applicationName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchTheme.primaryText)
                        Text(state.statusText)
                            .font(.system(size: 9.5))
                            .foregroundStyle(state.isRecoverable ? NotchTheme.destructive : NotchTheme.secondaryText)
                    }
                    Spacer()
                    if state.canReconnect {
                        Button("Reconnect") { viewModel.reconnectMedia(source) }
                            .buttonStyle(SettingsButtonStyle())
                    } else if state.requiresAppRestart {
                        Button("Quit App", action: viewModel.hooks.onQuit)
                            .buttonStyle(SettingsButtonStyle())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 46)

                if state.requiresSystemSettings {
                    HStack {
                        Spacer()
                        Button("Open System Settings", action: viewModel.openMediaAutomationSettings)
                            .buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                if index < NowPlayingSource.allCases.count - 1 {
                    SettingsDivider(leadingInset: 44)
                }
            }
        }
    }

    private var studioLightSection: some View {
        SettingsGroup(title: "Studio Light", subtitle: "Experimental MOLUS G60 control") {
            HStack(spacing: 8) {
                SettingsRowIcon(symbol: "laser.burst")
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        viewModel.studioLightState.configuredDevice?.name
                            ?? "MOLUS G60"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                    Text(viewModel.studioLightState.connection.statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(studioLightStatusColor)
                        .lineLimit(1)
                }
                Spacer()
                studioLightActions
            }
            .padding(.horizontal, 10)
            .frame(height: 46)

            if !viewModel.studioLightState.discoveredDevices.isEmpty,
               !viewModel.studioLightState.isConfigured {
                ForEach(viewModel.studioLightState.discoveredDevices) { device in
                    SettingsDivider(leadingInset: 44)
                    HStack(spacing: 8) {
                        SettingsRowIcon(symbol: "dot.radiowaves.left.and.right")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(NotchTheme.primaryText)
                            if let rssi = device.rssi {
                                Text("Signal \(rssi) dBm")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NotchTheme.tertiaryText)
                            }
                        }
                        Spacer()
                        Button("Pair") {
                            viewModel.pairStudioLight(device)
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                }
            }

            SettingsDivider()
            Text(
                "Keep the fixture powered and disconnect it from ZY Vega before connecting here."
            )
            .font(.system(size: 9))
            .foregroundStyle(NotchTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var studioLightActions: some View {
        let state = viewModel.studioLightState
        if state.connection == .permissionDenied {
            Button("System Settings", action: viewModel.openBluetoothSettings)
                .buttonStyle(SettingsButtonStyle())
        } else if state.isConfigured {
            if state.connection.canRetry && !state.connection.isConnected {
                Button("Retry", action: viewModel.retryStudioLight)
                    .buttonStyle(SettingsButtonStyle())
            } else if state.connection.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 27, height: 27)
            }
            Button("Forget", action: viewModel.forgetStudioLight)
                .buttonStyle(SettingsButtonStyle())
        } else if state.connection == .scanning {
            Button("Stop", action: viewModel.cancelStudioLightPairing)
                .buttonStyle(SettingsButtonStyle())
        } else if state.connection == .connecting {
            ProgressView()
                .controlSize(.small)
                .frame(width: 27, height: 27)
        } else {
            Button("Pair…", action: viewModel.startStudioLightPairing)
                .buttonStyle(SettingsButtonStyle())
        }
    }

    private var studioLightStatusColor: Color {
        switch viewModel.studioLightState.connection {
        case .connected:
            NotchTheme.secondaryText
        case .connecting, .scanning:
            NotchTheme.primaryAccent
        case .notConfigured:
            NotchTheme.secondaryText
        default:
            NotchTheme.destructive.opacity(0.88)
        }
    }

    private var privacyAndDataSection: some View {
        SettingsGroup(title: "Privacy & Data", subtitle: "Everything is stored only on this Mac") {
            HStack(spacing: 8) {
                SettingsRowIcon(symbol: "externaldrive")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture library")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.primaryText)
                    Text("Move a local backup in or out")
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                Spacer()
                Button("Import…", action: viewModel.hooks.onImport)
                    .buttonStyle(SettingsButtonStyle())
                Button("Export…", action: viewModel.hooks.onExport)
                    .buttonStyle(SettingsButtonStyle())
            }
            .padding(.horizontal, 10)
            .frame(height: 46)

            SettingsDivider()
            HStack(spacing: 8) {
                SettingsRowIcon(symbol: "arrow.triangle.2.circlepath")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.primaryText)
                    Text("Version \(Self.appVersion)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                Spacer()
                if viewModel.updatesEnabled {
                    Button("Check for Updates…", action: viewModel.hooks.onCheckForUpdates)
                        .buttonStyle(SettingsButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var quitAction: some View {
        SettingsGroup(title: "Application") {
            Button(action: viewModel.hooks.onQuit) {
                HStack(spacing: 10) {
                    SettingsRowIcon(symbol: "power")
                    Text("Quit Notch Capture")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.destructive.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .notchHitTarget(Rectangle())
            }
            .buttonStyle(NotchPressButtonStyle(pressedScale: 0.995, pressedOpacity: 0.82))
            .notchHitTarget(Rectangle())
            .accessibilityLabel("Quit Notch Capture")
        }
    }

    private func presentShortcutRecorder(_ request: AppViewModel.ShortcutRecordingRequest) {
        presentation.present(NotchModal(kind: .shortcut, title: "Record \(request.title)", message: "Press a shortcut that includes Control, Option, Shift, or Command.", textFieldLabel: nil, draft: request.currentValue, primaryTitle: "Waiting for keys", cancelTitle: "Cancel", onSubmit: { _ in "Press a key combination to record it." }, onCancel: {
            viewModel.hooks.onCancelShortcutRecording()
        }, onKeyRecording: { result in
            switch result {
            case let .success(recording):
                return viewModel.hooks.onCommitShortcutRecording(request.action, recording)
            case let .failure(failure):
                return failure.message
            }
        }))
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(NotchTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

private struct SettingsDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(NotchTheme.hairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .padding(.horizontal, 10)
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let control: Control

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            NotchToggle(title: title, showsTitle: false, isOn: $isOn)
        }
    }
}

private struct SettingsRowIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(NotchTheme.secondaryText)
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? NotchTheme.primaryAccent : Color.white.opacity(0.7))
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}
