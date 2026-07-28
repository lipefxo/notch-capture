import AppKit
import Combine
@preconcurrency import UserNotifications

enum CameraStartupFramingPolicy {
    static func target(
        presetState: CameraPresetState,
        legacyAim: CameraAim?
    ) -> CameraPreset? {
        if let selectedSlot = presetState.selectedSlot,
           let selectedPreset = presetState.preset(in: selectedSlot) {
            return selectedPreset
        }
        return legacyAim.map { CameraPreset(pan: $0.pan, tilt: $0.tilt, zoom: nil) }
    }
}

extension AppCoordinator {
    private static let cameraPrimingDelay = Duration.milliseconds(120)
    private static let cameraGimbalSettleDelay = Duration.milliseconds(900)

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

    func configureCamera() {
        guard !previewMode else { return }
        cameraService.onStateChange = { [weak self] state in
            guard let self else { return }
            self.cameraPresentationTask?.cancel()
            self.cameraPresentationTask = nil
            // Controls are only discoverable once a device has been resolved,
            // so capabilities are read off the back of the running state rather
            // than guessed up front.
            if case .running = state {
                self.prepareCameraPresentation(state)
            } else {
                self.cameraControlService.detach()
                self.viewModel.cameraControls = .none
                self.viewModel.configureCameraPresets(.empty)
                self.viewModel.cameraPreview = state
            }
        }
    }

    private func prepareCameraPresentation(_ state: CameraService.PreviewState) {
        let startupPreset = attachCameraControls()
        let waitsForGimbal = viewModel.cameraControls.canMove
        cameraPresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if let startupPreset {
                let primed = self.cameraControlService.primePanTiltRestore(
                    pan: startupPreset.pan,
                    tilt: startupPreset.tilt
                )
                if primed {
                    try? await Task.sleep(for: Self.cameraPrimingDelay)
                    guard !Task.isCancelled else { return }
                }
                self.viewModel.applyCameraPreset(startupPreset)
            }

            if waitsForGimbal {
                try? await Task.sleep(for: Self.cameraGimbalSettleDelay)
                guard !Task.isCancelled else { return }
            }
            guard self.viewModel.surfaceState == .mirror,
                  self.cameraService.state == state else { return }
            self.viewModel.cameraPreview = state
            self.cameraPresentationTask = nil
        }
    }

    private func attachCameraControls() -> CameraPreset? {
        guard let uid = cameraService.activeDeviceUID else { return nil }
        cameraControlService.attach(deviceUID: uid)
        viewModel.cameraControls = cameraControlService.capabilities
        if let zoom = cameraControlService.zoom {
            viewModel.cameraZoom = zoom
        } else if let range = cameraControlService.capabilities.zoomRange {
            viewModel.cameraZoom = range.lowerBound
        }
        if let aim = cameraControlService.panTilt {
            viewModel.cameraPan = aim.pan
            viewModel.cameraTilt = aim.tilt
        }
        let presetState = cameraPresetStore.state(for: uid)
        viewModel.configureCameraPresets(presetState)
        return CameraStartupFramingPolicy.target(
            presetState: presetState,
            legacyAim: cameraAimStore.aim(for: uid)
        )
    }

    func persistCameraAim(pan: Double, tilt: Double) {
        guard let uid = cameraService.activeDeviceUID else { return }
        cameraAimStore.setAim(CameraAim(pan: pan, tilt: tilt), for: uid)
    }

    /// The mirror panel never becomes key, so the camera session follows the
    /// surface rather than any focus event: opening starts it, anything else
    /// stops it and turns the camera indicator light back off.
    func updateCameraSession(for state: AppViewModel.SurfaceState) {
        guard !previewMode else { return }
        if state == .mirror {
            cameraService.start()
        } else {
            cameraService.stop()
        }
    }

    func updateMediaActivityLevel(for state: AppViewModel.SurfaceState) {
        guard !previewMode else { return }
        let level: NowPlayingService.ActivityLevel = switch state {
        case .expanded, .settings: .full
        // The mirror shows no now-playing chrome, but closing it lands straight
        // back on the activity pill, so its data must not have gone stale.
        case .collapsed, .collapsedActivity, .confirmation, .pomodoroComplete, .mirror: .compact
        case .dormant, .drop, .onboarding: .hidden
        }
        nowPlayingService.setActivityLevel(level)
        if level != .hidden { nowPlayingService.refresh() }
    }

    func updateCollapsedActivityLayout() {
        guard let screen = displayLocator.pointerScreen,
              let geometry = displayLocator.geometry(for: screen) else { return }
        let simulatesNotch = previewMode && CommandLine.arguments.contains("--preview-hardware-notch")
        let simulatesExternalDisplay = previewMode
            && CommandLine.arguments.contains("--preview-external-display")
        viewModel.collapsedActivityLayout = AppViewModel.CollapsedActivityLayout(
            hasHardwareNotch: !simulatesExternalDisplay
                && (simulatesNotch || (geometry.notchRect != nil && geometry.safeAreaInsets.top > 0)),
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
        // The mirror is deliberately left alone: the user opened it to look at
        // something, and the finished timer is waiting when they next open the
        // inbox.
        case .expanded, .drop, .settings, .onboarding, .pomodoroComplete, .mirror:
            viewModel.isPomodoroCardVisible = true
        }
    }
}
