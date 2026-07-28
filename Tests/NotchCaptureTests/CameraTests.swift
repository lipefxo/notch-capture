import AVFoundation
import XCTest
@testable import NotchCapture

private final class PendingCameraStart: @unchecked Sendable {
    var completion: (@Sendable (Result<CameraService.RunningSession, CameraServiceError>) -> Void)?
    var startCount = 0
    var stopCount = 0
}

@MainActor
final class CameraServiceTests: XCTestCase {
    func testPreviewRemainsIdleUntilPreparedSessionCompletes() async {
        let pending = PendingCameraStart()
        let previewLayer = AVCaptureVideoPreviewLayer()
        let service = CameraService(
            authorizationStatus: { .authorized },
            startSession: {
                pending.startCount += 1
                pending.completion = $0
            },
            stopSession: {}
        )

        service.start()
        service.start()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(pending.startCount, 1)
        pending.completion?(.success(.init(deviceUID: "camera-a", previewLayer: previewLayer)))
        await Task.yield()

        XCTAssertEqual(service.activeDeviceUID, "camera-a")
        XCTAssertEqual(service.state, .running(previewLayer))
    }

    func testStoppedSessionIgnoresAStalePreparedPreview() async {
        let pending = PendingCameraStart()
        let previewLayer = AVCaptureVideoPreviewLayer()
        let service = CameraService(
            authorizationStatus: { .authorized },
            startSession: { pending.completion = $0 },
            stopSession: { pending.stopCount += 1 }
        )

        service.start()
        service.stop()
        pending.completion?(.success(.init(deviceUID: "camera-a", previewLayer: previewLayer)))
        await Task.yield()

        XCTAssertNil(service.activeDeviceUID)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(pending.stopCount, 1)
    }

    func testSessionPreparationFailureBecomesUnavailable() async {
        let pending = PendingCameraStart()
        let service = CameraService(
            authorizationStatus: { .authorized },
            startSession: { pending.completion = $0 },
            stopSession: { pending.stopCount += 1 }
        )

        service.start()
        pending.completion?(.failure(.landscapeUnavailable))
        await Task.yield()

        XCTAssertNil(service.activeDeviceUID)
        XCTAssertEqual(service.state, .unavailable)
        XCTAssertEqual(pending.stopCount, 1)
    }
}

final class CameraLandscapePolicyTests: XCTestCase {
    func testPreferredFormatFavorsLandscapeNear720pSixteenByNine() {
        let dimensions = [
            CameraFormatDimensions(width: 1080, height: 1920),
            CameraFormatDimensions(width: 1920, height: 1080),
            CameraFormatDimensions(width: 1280, height: 720),
            CameraFormatDimensions(width: 640, height: 480),
        ]

        XCTAssertEqual(CameraLandscapePolicy.preferredFormatIndex(in: dimensions), 2)
    }

    func testPortraitOnlyCameraHasNoForcedLandscapeFormat() {
        let dimensions = [
            CameraFormatDimensions(width: 720, height: 1280),
            CameraFormatDimensions(width: 1080, height: 1920),
        ]

        XCTAssertNil(CameraLandscapePolicy.preferredFormatIndex(in: dimensions))
    }
}

final class CameraPanTiltRestorePolicyTests: XCTestCase {
    private let panRange = -522000.0...522000.0
    private let tiltRange = -324000.0...360000.0

    func testMatchingNativeTargetGetsAOneDegreePrimingCommand() {
        let target = CameraAim(pan: 0, tilt: -64800)

        let primingAim = CameraPanTiltRestorePolicy.primingAim(
            current: target,
            target: target,
            panRange: panRange,
            tiltRange: tiltRange
        )

        XCTAssertEqual(primingAim, CameraAim(pan: 3600, tilt: -64800))
    }

    func testDifferentNativeTargetNeedsNoPrimingCommand() {
        let primingAim = CameraPanTiltRestorePolicy.primingAim(
            current: CameraAim(pan: 0, tilt: 0),
            target: CameraAim(pan: 0, tilt: -64800),
            panRange: panRange,
            tiltRange: tiltRange
        )

        XCTAssertNil(primingAim)
    }

    func testPrimingMovesInwardAtTheUpperPanLimit() {
        let target = CameraAim(pan: panRange.upperBound, tilt: 0)

        let primingAim = CameraPanTiltRestorePolicy.primingAim(
            current: target,
            target: target,
            panRange: panRange,
            tiltRange: tiltRange
        )

        XCTAssertEqual(
            primingAim,
            CameraAim(pan: panRange.upperBound - CameraPanTiltRestorePolicy.primingStep, tilt: 0)
        )
    }
}

final class CameraStartupFramingPolicyTests: XCTestCase {
    func testSelectedPresetTakesPrecedenceOverLegacyAim() {
        let selected = CameraPreset(pan: 7200, tilt: -64800, zoom: 160)
        var state = CameraPresetState.empty
        state.setPreset(selected, in: .two)

        XCTAssertEqual(
            CameraStartupFramingPolicy.target(
                presetState: state,
                legacyAim: CameraAim(pan: -3600, tilt: 3600)
            ),
            selected
        )
    }

    func testLegacyAimIsUsedUntilAPresetIsSelected() {
        let legacy = CameraAim(pan: -3600, tilt: 10800)

        XCTAssertEqual(
            CameraStartupFramingPolicy.target(
                presetState: .empty,
                legacyAim: legacy
            ),
            CameraPreset(pan: legacy.pan, tilt: legacy.tilt, zoom: nil)
        )
        XCTAssertNil(
            CameraStartupFramingPolicy.target(
                presetState: .empty,
                legacyAim: nil
            )
        )
    }
}

final class CameraPresetControlContentTests: XCTestCase {
    func testButtonsDescribeFilledEmptyAndSelectedSlots() {
        let preset = CameraPreset(pan: 0, tilt: -64800, zoom: 130)
        let states = CameraPresetControlContent.buttonStates(
            presets: [.two: preset],
            selectedSlot: .two
        )

        XCTAssertEqual(
            states,
            [
                CameraPresetButtonState(slot: .one, status: "Empty", isEnabled: false, isSelected: false),
                CameraPresetButtonState(slot: .two, status: "Selected", isEnabled: true, isSelected: true),
                CameraPresetButtonState(slot: .three, status: "Empty", isEnabled: false, isSelected: false),
            ]
        )
        XCTAssertEqual(
            CameraPresetControlContent.saveTitle(for: .one, presets: [.two: preset]),
            "Save to Position 1"
        )
        XCTAssertEqual(
            CameraPresetControlContent.saveTitle(for: .two, presets: [.two: preset]),
            "Replace Position 2"
        )
    }

    func testPresetButtonRequiresPanAndTiltTravel() {
        XCTAssertFalse(
            CameraPresetControlContent.isAvailable(
                for: .init(zoomRange: 100...400, canRecenter: false)
            )
        )
        XCTAssertTrue(
            CameraPresetControlContent.isAvailable(
                for: .init(
                    zoomRange: nil,
                    canRecenter: true,
                    panRange: -7200...7200,
                    tiltRange: -3600...3600
                )
            )
        )
    }
}

@MainActor
final class CameraAimStoreTests: XCTestCase {
    func testAimSurvivesAStoreRecreationAndIsIsolatedByDevice() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CameraAimStore(defaults: defaults)

        store.setAim(CameraAim(pan: 7200, tilt: -3600), for: "camera-a")
        store.setAim(CameraAim(pan: -14400, tilt: 10800), for: "camera-b")

        let reloaded = CameraAimStore(defaults: defaults)
        XCTAssertEqual(reloaded.aim(for: "camera-a"), CameraAim(pan: 7200, tilt: -3600))
        XCTAssertEqual(reloaded.aim(for: "camera-b"), CameraAim(pan: -14400, tilt: 10800))
        XCTAssertNil(reloaded.aim(for: "camera-c"))
    }

    func testCorruptPayloadIsIgnoredAndReplacedByTheNextAim() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not a property list".utf8), forKey: CameraAimStore.defaultsKey)
        let store = CameraAimStore(defaults: defaults)

        XCTAssertNil(store.aim(for: "camera-a"))

        store.setAim(CameraAim(pan: 0, tilt: 0), for: "camera-a")

        XCTAssertEqual(store.aim(for: "camera-a"), CameraAim(pan: 0, tilt: 0))
    }

    func testRestoredAimIsClampedBeforeItReachesTheCamera() {
        var applied: [CameraAim] = []
        var hooks = AppViewModel.Hooks()
        hooks.onMoveCamera = { applied.append(CameraAim(pan: $0, tilt: $1)) }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.cameraControls = .init(
            zoomRange: nil,
            canRecenter: true,
            panRange: -7200...7200,
            tiltRange: -3600...3600
        )

        viewModel.restoreCameraAim(toPan: 500_000, tilt: -500_000)

        XCTAssertEqual(viewModel.cameraPan, 7200)
        XCTAssertEqual(viewModel.cameraTilt, -3600)
        XCTAssertEqual(applied, [CameraAim(pan: 7200, tilt: -3600)])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "CameraAimStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}

@MainActor
final class CameraPresetStoreTests: XCTestCase {
    func testSlotsSelectionAndOverwriteSurviveStoreRecreationPerCamera() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CameraPresetStore(defaults: defaults)
        let first = CameraPreset(pan: 0, tilt: -64800, zoom: 130)
        let replacement = CameraPreset(pan: 7200, tilt: -72000, zoom: 160)
        let otherCamera = CameraPreset(pan: -3600, tilt: 18000, zoom: nil)

        store.setPreset(first, in: .one, for: "camera-a")
        store.setPreset(otherCamera, in: .three, for: "camera-b")
        store.setPreset(replacement, in: .one, for: "camera-a")

        let reloaded = CameraPresetStore(defaults: defaults)
        XCTAssertEqual(reloaded.state(for: "camera-a").preset(in: .one), replacement)
        XCTAssertEqual(reloaded.state(for: "camera-a").selectedSlot, .one)
        XCTAssertEqual(reloaded.state(for: "camera-b").preset(in: .three), otherCamera)
        XCTAssertEqual(reloaded.state(for: "camera-b").selectedSlot, .three)
    }

    func testSelectionChangesOnlyForFilledSlots() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CameraPresetStore(defaults: defaults)
        let preset = CameraPreset(pan: 0, tilt: 0, zoom: 100)
        store.setPreset(preset, in: .one, for: "camera-a")

        store.select(.three, for: "camera-a")
        XCTAssertEqual(store.state(for: "camera-a").selectedSlot, .one)

        store.setPreset(preset, in: .three, for: "camera-a")
        store.select(.one, for: "camera-a")
        XCTAssertEqual(store.state(for: "camera-a").selectedSlot, .one)
    }

    func testCorruptPresetPayloadFallsBackToEmptyState() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not a property list".utf8), forKey: CameraPresetStore.defaultsKey)

        XCTAssertEqual(
            CameraPresetStore(defaults: defaults).state(for: "camera-a"),
            .empty
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "CameraPresetStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}

@MainActor
final class CameraPresetViewModelTests: XCTestCase {
    private let capabilities = CameraControlService.Capabilities(
        zoomRange: 100...400,
        canRecenter: true,
        panRange: -7200...7200,
        tiltRange: -3600...3600
    )

    func testSavingCapturesFramingAndManualChangesDoNotOverwriteIt() {
        var savedSlots: [CameraPresetSlot] = []
        var savedPresets: [CameraPreset] = []
        var hooks = AppViewModel.Hooks()
        hooks.onSaveCameraPreset = {
            savedSlots.append($0)
            savedPresets.append($1)
        }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.cameraControls = capabilities
        viewModel.cameraPan = 7200
        viewModel.cameraTilt = -3600
        viewModel.cameraZoom = 160

        viewModel.saveCameraPreset(in: .two)
        let saved = CameraPreset(pan: 7200, tilt: -3600, zoom: 160)

        XCTAssertEqual(viewModel.cameraPresets[.two], saved)
        XCTAssertEqual(viewModel.selectedCameraPresetSlot, .two)
        XCTAssertEqual(savedSlots, [.two])
        XCTAssertEqual(savedPresets, [saved])

        viewModel.moveCamera(toPan: 0, tilt: 0)
        viewModel.stepCameraZoom(by: 1)

        XCTAssertEqual(viewModel.cameraPresets[.two], saved)
        XCTAssertEqual(viewModel.selectedCameraPresetSlot, .two)
    }

    func testRecallClampsEverySupportedValueAndEmptySlotIsInert() {
        var moves: [CameraAim] = []
        var zooms: [Double] = []
        var selections: [CameraPresetSlot] = []
        var hooks = AppViewModel.Hooks()
        hooks.onMoveCamera = { moves.append(CameraAim(pan: $0, tilt: $1)) }
        hooks.onSetCameraZoom = { zooms.append($0) }
        hooks.onSelectCameraPreset = { selections.append($0) }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.cameraControls = capabilities
        var state = CameraPresetState.empty
        state.setPreset(
            CameraPreset(pan: 500_000, tilt: -500_000, zoom: 900),
            in: .three
        )
        viewModel.configureCameraPresets(state)

        viewModel.recallCameraPreset(in: .one)
        XCTAssertTrue(moves.isEmpty)
        XCTAssertTrue(zooms.isEmpty)

        viewModel.recallCameraPreset(in: .three)

        XCTAssertEqual(viewModel.cameraPan, 7200)
        XCTAssertEqual(viewModel.cameraTilt, -3600)
        XCTAssertEqual(viewModel.cameraZoom, 400)
        XCTAssertEqual(moves, [CameraAim(pan: 7200, tilt: -3600)])
        XCTAssertEqual(zooms, [400])
        XCTAssertEqual(selections, [.three])
    }
}
