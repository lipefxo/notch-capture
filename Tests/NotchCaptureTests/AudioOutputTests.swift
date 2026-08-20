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

    func testViewModelForwardsAudioActions() {
        var calls: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onRefreshAudioOutputs = { calls.append("refresh") }
        hooks.onSelectAudioOutput = { calls.append("select:\($0.rawValue)") }
        let viewModel = AppViewModel(hooks: hooks)

        viewModel.refreshAudioOutputs()
        viewModel.selectAudioOutput(.edifier)

        XCTAssertEqual(calls, ["refresh", "select:edifier"])
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

    func startObserving() throws { startCount += 1 }
    func stopObserving() { stopCount += 1 }
    func sendChange() { onChange?() }
}
