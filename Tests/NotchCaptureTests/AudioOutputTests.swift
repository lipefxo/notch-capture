import XCTest
@testable import NotchCapture

final class AudioOutputModelTests: XCTestCase {
    func testTargetsKeepStableOrderAndMatchNormalizedHardwareNames() {
        XCTAssertEqual(AudioOutputTarget.allCases, [.airPods, .edifier, .headphones])
        XCTAssertTrue(AudioOutputTarget.airPods.matches(deviceName: "Felipe's AirPods Pro"))
        XCTAssertTrue(AudioOutputTarget.edifier.matches(deviceName: "edifier m60"))
        XCTAssertTrue(AudioOutputTarget.headphones.matches(deviceName: "FIFINE-AMPLI1"))
        XCTAssertFalse(AudioOutputTarget.headphones.matches(deviceName: "fifine Ampli2"))
    }

    func testViewStateRequiresBothDefaultsForSelection() {
        let state = AudioOutputViewState(
            availableTargets: [.edifier, .headphones],
            mediaTarget: .edifier,
            systemTarget: .headphones,
            mediaDeviceName: "EDIFIER M60",
            systemDeviceName: "fifine Ampli1"
        )

        XCTAssertFalse(state.isSelected(.edifier))
        XCTAssertFalse(state.isSelected(.headphones))
        XCTAssertEqual(
            state.accessibilityCurrentOutput,
            "Media: Edifier, system sounds: Headphones"
        )
    }

    func testSegmentPresentationDescribesEveryVisibleState() {
        let selected = AudioOutputSegmentPresentation.make(
            target: .edifier,
            state: .preview
        )
        let unavailable = AudioOutputSegmentPresentation.make(
            target: .airPods,
            state: .preview
        )
        let available = AudioOutputSegmentPresentation.make(
            target: .headphones,
            state: .preview
        )

        XCTAssertEqual(selected.accessibilityValue, "Selected")
        XCTAssertEqual(unavailable.accessibilityValue, "Unavailable")
        XCTAssertEqual(available.accessibilityValue, "Available")
    }

    func testVolumePresentationClampsValuesAndTreatsZeroAsMuted() {
        var state = AudioVolumeViewState.preview
        state.value = 1.4
        XCTAssertEqual(state.clampedValue, 1)
        XCTAssertEqual(state.percentageText, "100%")
        XCTAssertEqual(AudioVolumePresentation.symbolName(for: state), "speaker.wave.3.fill")

        state.value = 0
        XCTAssertTrue(state.isEffectivelyMuted)
        XCTAssertEqual(AudioVolumePresentation.symbolName(for: state), "speaker.slash.fill")

        state = .empty
        state.deviceName = "USB Interface"
        XCTAssertEqual(state.percentageText, "Device controls")
        XCTAssertEqual(state.accessibilityValue, "Use controls on USB Interface")
    }

    func testChannelBackedVolumeScalingPreservesBalance() {
        XCTAssertEqual(
            AudioVolumeChannelScaling.values(
                preservingBalance: [0.8, 0.4],
                target: 0.5
            ),
            [0.5, 0.25]
        )
        XCTAssertEqual(
            AudioVolumeChannelScaling.values(
                preservingBalance: [0, 0],
                target: 0.3
            ),
            [0.3, 0.3]
        )
    }
}

@MainActor
final class AudioOutputServiceTests: XCTestCase {
    func testRefreshFindsOnlyAliveSelectableOutputDevices() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [
            device(1, "Felipe’s AirPods Pro", alive: false),
            device(2, "EDIFIER M60"),
            device(3, "fifine Ampli1", output: false),
            device(4, "fifine Ampli1"),
        ]
        hardware.mediaID = 2
        hardware.systemID = 2
        let service = AudioOutputService(hardware: hardware)

        service.refresh()

        XCTAssertEqual(service.state.availableTargets, [.edifier, .headphones])
        XCTAssertTrue(service.state.isSelected(.edifier))
        XCTAssertFalse(service.state.isAvailable(.airPods))
    }

    func testSelectionWritesBothDefaultsAndPublishesReadback() throws {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [
            device(2, "EDIFIER M60"),
            device(4, "fifine Ampli1"),
        ]
        hardware.mediaID = 2
        hardware.systemID = 2
        let service = AudioOutputService(hardware: hardware)
        var published: [AudioOutputViewState] = []
        service.onChange = { published.append($0) }

        try service.select(.headphones)

        XCTAssertEqual(hardware.outputWrites, [4])
        XCTAssertEqual(hardware.systemWrites, [4])
        XCTAssertEqual(hardware.mediaID, 4)
        XCTAssertEqual(hardware.systemID, 4)
        XCTAssertTrue(service.state.isSelected(.headphones))
        XCTAssertEqual(published.last, service.state)
    }

    func testUnavailableTargetNeverWritesHardware() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(2, "EDIFIER M60")]
        let service = AudioOutputService(hardware: hardware)

        XCTAssertThrowsError(try service.select(.airPods)) { error in
            XCTAssertEqual(error as? AudioOutputServiceError, .unavailable(.airPods))
        }
        XCTAssertTrue(hardware.outputWrites.isEmpty)
        XCTAssertTrue(hardware.systemWrites.isEmpty)
    }

    func testHardwareFailureRefreshesActualSplitState() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [
            device(2, "EDIFIER M60"),
            device(4, "fifine Ampli1"),
        ]
        hardware.mediaID = 2
        hardware.systemID = 2
        hardware.systemWriteError = FakeCoreAudioError.writeFailed
        let service = AudioOutputService(hardware: hardware)

        XCTAssertThrowsError(try service.select(.headphones))
        XCTAssertEqual(service.state.mediaTarget, .headphones)
        XCTAssertEqual(service.state.systemTarget, .edifier)
        XCTAssertFalse(service.state.isSelected(.headphones))
    }

    func testObservationLifecycleAndExternalChangesRefreshState() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(2, "EDIFIER M60")]
        hardware.mediaID = 2
        hardware.systemID = 2
        let service = AudioOutputService(hardware: hardware)

        service.start()
        XCTAssertEqual(hardware.startCount, 1)
        XCTAssertTrue(service.state.isSelected(.edifier))

        hardware.deviceList.append(device(4, "fifine Ampli1"))
        hardware.mediaID = 4
        hardware.systemID = 4
        hardware.sendChange()

        XCTAssertTrue(service.state.isAvailable(.headphones))
        XCTAssertTrue(service.state.isSelected(.headphones))

        service.stop()
        XCTAssertEqual(hardware.stopCount, 1)
    }

    func testRefreshPublishesCurrentOutputVolumeAndObservationTarget() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(2, "EDIFIER M60")]
        hardware.mediaID = 2
        hardware.systemID = 2
        hardware.volumeStates[2] = AudioVolumeViewState(
            value: 0.42,
            isMuted: false,
            canSetVolume: true,
            canSetMute: true,
            deviceName: nil
        )
        let service = AudioOutputService(hardware: hardware)

        service.refresh()

        XCTAssertEqual(service.state.volume.value, 0.42)
        XCTAssertEqual(service.state.volume.deviceName, "EDIFIER M60")
        XCTAssertEqual(hardware.observedDeviceIDs, [2])
    }

    func testVolumeAndMuteWritesClampAndPublishHardwareReadback() throws {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(2, "EDIFIER M60")]
        hardware.mediaID = 2
        hardware.systemID = 2
        hardware.volumeStates[2] = .preview
        let service = AudioOutputService(hardware: hardware)
        service.refresh()

        try service.setVolume(1.6)
        try service.setMuted(true)

        XCTAssertEqual(hardware.volumeWrites.map(\.volume), [1])
        XCTAssertEqual(hardware.volumeWrites.map(\.deviceID), [2])
        XCTAssertEqual(hardware.muteWrites.map(\.isMuted), [true])
        XCTAssertEqual(service.state.volume.value, 1)
        XCTAssertTrue(service.state.volume.isMuted)
    }

    func testUnsupportedVolumeAndMuteNeverWriteHardware() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(4, "fifine Ampli1")]
        hardware.mediaID = 4
        hardware.systemID = 4
        let service = AudioOutputService(hardware: hardware)
        service.refresh()

        XCTAssertThrowsError(try service.setVolume(0.5)) { error in
            XCTAssertEqual(
                error as? AudioOutputServiceError,
                .volumeUnavailable("fifine Ampli1")
            )
        }
        XCTAssertThrowsError(try service.setMuted(true)) { error in
            XCTAssertEqual(
                error as? AudioOutputServiceError,
                .muteUnavailable("fifine Ampli1")
            )
        }
        XCTAssertTrue(hardware.volumeWrites.isEmpty)
        XCTAssertTrue(hardware.muteWrites.isEmpty)
    }

    func testVolumeWriteFailureRefreshesHardwareStateAndReportsError() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [device(2, "EDIFIER M60")]
        hardware.mediaID = 2
        hardware.systemID = 2
        hardware.volumeStates[2] = .preview
        hardware.volumeWriteError = FakeCoreAudioError.writeFailed
        let service = AudioOutputService(hardware: hardware)
        service.refresh()

        XCTAssertThrowsError(try service.setVolume(0.1)) { error in
            XCTAssertEqual(
                error as? AudioOutputServiceError,
                .volumeChangeFailed("Write failed")
            )
        }
        XCTAssertEqual(service.state.volume.value, 0.64)
    }

    func testExternalVolumeChangeAndOutputSwitchRefreshAndRebind() {
        let hardware = FakeCoreAudioHardware()
        hardware.deviceList = [
            device(2, "EDIFIER M60"),
            device(4, "fifine Ampli1"),
        ]
        hardware.mediaID = 2
        hardware.systemID = 2
        hardware.volumeStates[2] = .preview
        hardware.volumeStates[4] = AudioVolumeViewState(
            value: 0.25,
            isMuted: true,
            canSetVolume: true,
            canSetMute: true,
            deviceName: nil
        )
        let service = AudioOutputService(hardware: hardware)
        service.start()

        hardware.volumeStates[2]?.value = 0.8
        hardware.sendChange()
        XCTAssertEqual(service.state.volume.value, 0.8)

        hardware.mediaID = 4
        hardware.systemID = 4
        hardware.sendChange()
        XCTAssertEqual(service.state.volume.value, 0.25)
        XCTAssertTrue(service.state.volume.isMuted)
        XCTAssertEqual(hardware.observedDeviceIDs.suffix(1), [4])
    }

    func testViewModelForwardsAudioActions() {
        var calls: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onRefreshAudioOutputs = { calls.append("refresh") }
        hooks.onSelectAudioOutput = { calls.append("select:\($0.rawValue)") }
        hooks.onSetOutputVolume = { calls.append("volume:\($0)") }
        hooks.onSetOutputMuted = { calls.append("muted:\($0)") }
        let viewModel = AppViewModel(hooks: hooks)

        viewModel.refreshAudioOutputs()
        viewModel.selectAudioOutput(.edifier)
        viewModel.setOutputVolume(0.75)
        viewModel.setOutputMuted(true)

        XCTAssertEqual(calls, ["refresh", "select:edifier", "volume:0.75", "muted:true"])
    }

    func testFocusedVolumeSurfaceReturnsToCurrentIdleState() {
        let idle = AppViewModel(surfaceState: .collapsed)
        idle.openVolumeControl()
        XCTAssertEqual(idle.surfaceState, .volume)
        idle.closeVolumeControl()
        XCTAssertEqual(idle.surfaceState, .collapsed)

        let activity = AppViewModel(
            surfaceState: .collapsedActivity,
            nowPlaying: NowPlayingSnapshot(
                source: .spotify,
                trackKey: "track",
                title: "Title",
                artist: "Artist",
                album: "Album",
                duration: 100,
                isPlaying: true,
                position: 20,
                positionAnchor: .now,
                artworkURL: nil
            )
        )
        activity.openVolumeControl()
        activity.handleDismissalRequest(.externalClick)
        XCTAssertEqual(activity.surfaceState, .collapsedActivity)

        let hidden = AppViewModel(surfaceState: .collapsed)
        hidden.openVolumeControl()
        hidden.setIdlePillHidden(true)
        XCTAssertEqual(hidden.surfaceState, .volume)
        hidden.closeVolumeControl()
        XCTAssertEqual(hidden.surfaceState, .dormant)
    }

    private func device(
        _ id: UInt32,
        _ name: String,
        alive: Bool = true,
        output: Bool = true,
        canDefault: Bool = true,
        canSystem: Bool = true
    ) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            name: name,
            isAlive: alive,
            hasOutput: output,
            canBeDefault: canDefault,
            canBeSystemDefault: canSystem
        )
    }
}

private enum FakeCoreAudioError: LocalizedError {
    case writeFailed

    var errorDescription: String? { "Write failed" }
}

@MainActor
private final class FakeCoreAudioHardware: CoreAudioHardwareAccessing {
    var onChange: (@MainActor () -> Void)?
    var deviceList: [AudioOutputDevice] = []
    var mediaID: UInt32?
    var systemID: UInt32?
    var outputWrites: [UInt32] = []
    var systemWrites: [UInt32] = []
    var systemWriteError: Error?
    var volumeWriteError: Error?
    var muteWriteError: Error?
    var volumeStates: [UInt32: AudioVolumeViewState] = [:]
    var volumeWrites: [(volume: Double, deviceID: UInt32)] = []
    var muteWrites: [(isMuted: Bool, deviceID: UInt32)] = []
    var observedDeviceIDs: [UInt32?] = []
    var startCount = 0
    var stopCount = 0

    func devices() throws -> [AudioOutputDevice] { deviceList }
    func defaultOutputDeviceID() throws -> UInt32? { mediaID }
    func defaultSystemOutputDeviceID() throws -> UInt32? { systemID }

    func setDefaultOutputDeviceID(_ id: UInt32) throws {
        outputWrites.append(id)
        mediaID = id
    }

    func setDefaultSystemOutputDeviceID(_ id: UInt32) throws {
        systemWrites.append(id)
        if let systemWriteError { throw systemWriteError }
        systemID = id
    }

    func volumeState(for deviceID: UInt32) throws -> AudioVolumeViewState {
        volumeStates[deviceID] ?? .empty
    }

    func setVolume(_ volume: Double, for deviceID: UInt32) throws {
        volumeWrites.append((volume, deviceID))
        if let volumeWriteError { throw volumeWriteError }
        volumeStates[deviceID]?.value = volume
    }

    func setMuted(_ isMuted: Bool, for deviceID: UInt32) throws {
        muteWrites.append((isMuted, deviceID))
        if let muteWriteError { throw muteWriteError }
        volumeStates[deviceID]?.isMuted = isMuted
    }

    func observeVolumeAndMute(on deviceID: UInt32?) throws {
        observedDeviceIDs.append(deviceID)
    }

    func startObserving() throws { startCount += 1 }
    func stopObserving() { stopCount += 1 }
    func sendChange() { onChange?() }
}
