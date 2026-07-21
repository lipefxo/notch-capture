import AppKit
import Combine
@preconcurrency import UserNotifications

extension AppCoordinator {
    func configureMedia() {
        guard !previewMode else { return }

        nowPlayingService.onPresentationChange = { [weak self] presentation in
            guard let self else { return }
            let previousTrackKey = self.viewModel.nowPlaying?.trackKey
            self.viewModel.nowPlayingPresentation = presentation
            self.viewModel.nowPlaying = presentation?.snapshot
            if presentation?.snapshot.trackKey != previousTrackKey {
                self.viewModel.nowPlayingArtwork = nil
            }
            self.refreshIdleActivitySurface()
        }
        nowPlayingService.onArtworkChange = { [weak self] trackKey, artwork in
            guard let self, self.viewModel.nowPlaying?.trackKey == trackKey else { return }
            self.viewModel.nowPlayingArtwork = artwork
        }
        nowPlayingService.onSourceStatusChange = { [weak self] source, state in
            self?.viewModel.mediaConnectionStates[source] = state
        }

        pomodoroService.onChange = { [weak self] state in
            guard let self else { return }
            self.viewModel.pomodoro = state
            self.refreshIdleActivitySurface()
        }
        pomodoroService.onCompleted = { [weak self] in
            self?.handlePomodoroCompletion()
        }
        viewModel.pomodoro = pomodoroService.state
        for source in NowPlayingSource.allCases {
            viewModel.mediaConnectionStates[source] = nowPlayingService.connectionState(for: source)
        }
    }

    func updateMediaActivityLevel(for state: AppViewModel.SurfaceState) {
        guard !previewMode else { return }
        let level: NowPlayingService.ActivityLevel = switch state {
        case .expanded, .settings: .full
        case .collapsed, .collapsedActivity, .confirmation, .pomodoroComplete: .compact
        case .dormant, .drop, .onboarding: .hidden
        }
        nowPlayingService.setActivityLevel(level)
        if level != .hidden { nowPlayingService.refresh() }
    }

    func updateCollapsedActivityLayout() {
        guard let screen = displayLocator.pointerScreen,
              let geometry = displayLocator.geometry(for: screen) else { return }
        let simulatesNotch = previewMode && CommandLine.arguments.contains("--preview-hardware-notch")
        viewModel.collapsedActivityLayout = AppViewModel.CollapsedActivityLayout(
            hasHardwareNotch: simulatesNotch || (geometry.notchRect != nil && geometry.safeAreaInsets.top > 0),
            notchWidth: simulatesNotch ? 156 : (geometry.notchRect?.width ?? PanelMorphGeometry.virtualNotchSize.width),
            notchBandHeight: simulatesNotch ? 32 : max(geometry.notchRect?.height ?? 0, geometry.safeAreaInsets.top)
        )
    }

    private func refreshIdleActivitySurface() {
        guard [.collapsed, .collapsedActivity].contains(viewModel.surfaceState) else { return }
        let targetState = viewModel.idleSurfaceState
        guard viewModel.surfaceState != targetState else { return }
        viewModel.surfaceState = targetState
    }

    private func handlePomodoroCompletion() {
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = "Focus session complete"
            content.sound = .default
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }

        switch viewModel.surfaceState {
        case .collapsed, .collapsedActivity, .dormant:
            viewModel.surfaceState = .pomodoroComplete
        case .confirmation:
            // Preserve Capture's Undo window; the finished timer remains visible
            // the next time the user opens the expanded surface.
            break
        case .expanded, .drop, .settings, .onboarding, .pomodoroComplete:
            viewModel.isPomodoroCardVisible = true
        }
    }
}
