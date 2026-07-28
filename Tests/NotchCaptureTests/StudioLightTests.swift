import Foundation
import XCTest
@testable import NotchCapture

final class MolusG60ProtocolTests: XCTestCase {
    func testDiscoveryAcceptsG60AdvertisingVariants() {
        XCTAssertTrue(
            StudioLightDiscoveryPolicy.matches(
                advertisedName: "MOLUS G60_1234",
                peripheralName: nil,
                serviceUUIDs: []
            )
        )
        XCTAssertTrue(
            StudioLightDiscoveryPolicy.matches(
                advertisedName: "ZYPL103_ABCD",
                peripheralName: nil,
                serviceUUIDs: []
            )
        )
        XCTAssertTrue(
            StudioLightDiscoveryPolicy.matches(
                advertisedName: nil,
                peripheralName: nil,
                serviceUUIDs: ["FEE9"]
            )
        )
        XCTAssertTrue(
            StudioLightDiscoveryPolicy.matches(
                advertisedName: nil,
                peripheralName: nil,
                serviceUUIDs: [MolusG60Protocol.serviceUUID]
            )
        )
    }

    func testDiscoveryRejectsUnrelatedBluetoothDevices() {
        XCTAssertFalse(
            StudioLightDiscoveryPolicy.matches(
                advertisedName: "Living Room Speaker",
                peripheralName: "Speaker",
                serviceUUIDs: ["180A"]
            )
        )
        XCTAssertEqual(
            StudioLightDiscoveryPolicy.displayName(
                advertisedName: nil,
                peripheralName: nil
            ),
            "Possible MOLUS G60"
        )
    }

    func testCRCMatchesXmodemReferenceVector() {
        XCTAssertEqual(
            MolusG60Protocol.crc16Xmodem(Data("123456789".utf8)),
            0x31C3
        )
    }

    func testWriteCommandsMatchKnownG60Frames() {
        XCTAssertEqual(
            MolusG60Protocol.power(
                true,
                deviceNumber: 0x8003,
                sequence: 1
            ).hex,
            "243c0a00000101000810038001017e26"
        )
        XCTAssertEqual(
            MolusG60Protocol.power(
                false,
                deviceNumber: 0x8003,
                sequence: 2
            ).hex,
            "243c0a00000102000810038001002afe"
        )
        XCTAssertEqual(
            MolusG60Protocol.brightness(
                42.5,
                deviceNumber: 0x8003,
                sequence: 3
            ).hex,
            "243c0d0000010300011003800100002a42408a"
        )
        XCTAssertEqual(
            MolusG60Protocol.colorTemperature(
                5_600,
                deviceNumber: 0x8003,
                sequence: 4
            ).hex,
            "243c0b00000104000210038001e01531df"
        )
    }

    func testReadCommandsMatchKnownG60Frames() {
        XCTAssertEqual(
            MolusG60Protocol.read(
                .brightness,
                deviceNumber: 0x8003,
                sequence: 5
            ).hex,
            "243c0d00000105000110038000000000004e50"
        )
        XCTAssertEqual(
            MolusG60Protocol.read(
                .colorTemperature,
                deviceNumber: 0x8003,
                sequence: 6
            ).hex,
            "243c0b000001060002100380000000407c"
        )
        XCTAssertEqual(
            MolusG60Protocol.read(
                .power,
                deviceNumber: 0x8003,
                sequence: 7
            ).hex,
            "243c0a0000010700081003800000a585"
        )
        XCTAssertEqual(
            MolusG60Protocol.readDeviceNumber(sequence: 8).hex,
            "243c060000010800052005f4"
        )
        XCTAssertEqual(
            MolusG60Protocol.register(
                deviceNumber: 0x8000,
                sequence: 9
            ).hex,
            "243c0a00000109000600008000009104"
        )
    }

    func testResponseFramesDecodeKnownValues() throws {
        var brightnessPayload = Data([0x03, 0x80, 0x00])
        brightnessPayload.append(contentsOf: [0x00, 0x00, 0x2A, 0x42])
        let brightnessFrame = try MolusG60Protocol.decode(
            MolusG60Protocol.encode(
                command: .brightness,
                payload: brightnessPayload,
                sequence: 10
            )
        )
        XCTAssertEqual(
            try MolusG60Protocol.value(from: brightnessFrame),
            .brightness(42.5)
        )

        let temperatureFrame = try MolusG60Protocol.decode(
            MolusG60Protocol.encode(
                command: .colorTemperature,
                payload: Data([0x03, 0x80, 0x00, 0xE0, 0x15]),
                sequence: 11
            )
        )
        XCTAssertEqual(
            try MolusG60Protocol.value(from: temperatureFrame),
            .colorTemperature(5_600)
        )

        let powerFrame = try MolusG60Protocol.decode(
            MolusG60Protocol.encode(
                command: .power,
                payload: Data([0x03, 0x80, 0x00, 0x01]),
                sequence: 12
            )
        )
        XCTAssertEqual(try MolusG60Protocol.value(from: powerFrame), .power(true))

        let deviceIDFrame = try MolusG60Protocol.decode(
            MolusG60Protocol.encode(
                command: .deviceID,
                payload: Data([0x00, 0x80]),
                sequence: 13
            )
        )
        XCTAssertEqual(
            try MolusG60Protocol.value(from: deviceIDFrame),
            .deviceNumber(0x8000)
        )
    }

    func testMalformedFramesFailClosed() {
        XCTAssertThrowsError(try MolusG60Protocol.decode(Data([0x24, 0x3C])))

        var wrongMagic = MolusG60Protocol.power(
            true,
            deviceNumber: 0x8003,
            sequence: 1
        )
        wrongMagic[0] = 0
        XCTAssertThrowsError(try MolusG60Protocol.decode(wrongMagic)) { error in
            XCTAssertEqual(error as? MolusG60ProtocolError, .invalidMagic(0x3C00))
        }

        var wrongCRC = MolusG60Protocol.power(
            true,
            deviceNumber: 0x8003,
            sequence: 1
        )
        wrongCRC[wrongCRC.count - 1] ^= 0xFF
        XCTAssertThrowsError(try MolusG60Protocol.decode(wrongCRC)) { error in
            guard case .invalidCRC = error as? MolusG60ProtocolError else {
                return XCTFail("Expected an invalid CRC error, got \(error)")
            }
        }
    }

    func testRangesAndSequenceRolloverAreClamped() {
        XCTAssertEqual(MolusG60Protocol.clampedBrightness(-1), 0)
        XCTAssertEqual(MolusG60Protocol.clampedBrightness(101), 100)
        XCTAssertEqual(MolusG60Protocol.clampedBrightness(.nan), 0)
        XCTAssertEqual(MolusG60Protocol.clampedColorTemperature(2_000), 2_700)
        XCTAssertEqual(MolusG60Protocol.clampedColorTemperature(7_000), 6_500)
        XCTAssertEqual(MolusG60Protocol.nextSequence(after: 0), 1)
        XCTAssertEqual(MolusG60Protocol.nextSequence(after: 8), 9)
        XCTAssertEqual(MolusG60Protocol.nextSequence(after: .max), 1)
    }
}

@MainActor
final class StudioLightStateTests: XCTestCase {
    func testStoredDeviceLoadsWithoutStartingBluetoothAndForgetClearsIt() {
        let suiteName = "StudioLightStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let id = UUID()
        defaults.set(
            id.uuidString,
            forKey: StudioLightService.peripheralIDDefaultsKey
        )
        defaults.set(
            "MOLUS G60_TEST",
            forKey: StudioLightService.peripheralNameDefaultsKey
        )

        let service = StudioLightService(defaults: defaults)

        XCTAssertEqual(
            service.state.configuredDevice,
            StudioLightDevice(id: id, name: "MOLUS G60_TEST")
        )
        XCTAssertEqual(
            service.state.connection,
            .disconnected("Ready to connect")
        )

        service.forget()

        XCTAssertEqual(service.state, .empty)
        XCTAssertNil(
            defaults.string(forKey: StudioLightService.peripheralIDDefaultsKey)
        )
        XCTAssertNil(
            defaults.string(forKey: StudioLightService.peripheralNameDefaultsKey)
        )
    }

    func testReconnectBackoffIsBounded() {
        XCTAssertEqual(
            StudioLightReconnectPolicy.delay(forAttempt: 1),
            .seconds(1)
        )
        XCTAssertEqual(
            StudioLightReconnectPolicy.delay(forAttempt: 2),
            .seconds(2)
        )
        XCTAssertEqual(
            StudioLightReconnectPolicy.delay(forAttempt: 4),
            .seconds(8)
        )
        XCTAssertEqual(
            StudioLightReconnectPolicy.delay(forAttempt: 20),
            .seconds(10)
        )
    }

    func testViewModelForwardsEveryStudioLightAction() {
        let device = StudioLightDevice(id: UUID(), name: "MOLUS G60")
        var calls: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onStartStudioLightPairing = { calls.append("start") }
        hooks.onCancelStudioLightPairing = { calls.append("cancel") }
        hooks.onPairStudioLight = { calls.append("pair:\($0)") }
        hooks.onRetryStudioLight = { calls.append("retry") }
        hooks.onForgetStudioLight = { calls.append("forget") }
        hooks.onRefreshStudioLight = { calls.append("refresh") }
        hooks.onSetStudioLightPower = { calls.append("power:\($0)") }
        hooks.onSetStudioLightBrightness = {
            calls.append("brightness:\($0):\($1)")
        }
        hooks.onSetStudioLightColorTemperature = {
            calls.append("temperature:\($0):\($1)")
        }
        hooks.onOpenBluetoothSettings = { calls.append("settings") }
        let viewModel = AppViewModel(hooks: hooks)

        viewModel.startStudioLightPairing()
        viewModel.cancelStudioLightPairing()
        viewModel.pairStudioLight(device)
        viewModel.retryStudioLight()
        viewModel.forgetStudioLight()
        viewModel.refreshStudioLight()
        viewModel.setStudioLightPower(true)
        viewModel.setStudioLightBrightness(35, final: false)
        viewModel.setStudioLightColorTemperature(5_600, final: true)
        viewModel.openBluetoothSettings()

        XCTAssertEqual(
            calls,
            [
                "start",
                "cancel",
                "pair:\(device.id)",
                "retry",
                "forget",
                "refresh",
                "power:true",
                "brightness:35.0:false",
                "temperature:5600:true",
                "settings",
            ]
        )
    }

    func testStudioLightPopoverParticipatesInPresentationOwnership() {
        let coordinator = NotchPresentationCoordinator()
        coordinator.present(
            StudioLightPopover(
                anchor: CGRect(x: 10, y: 10, width: 28, height: 28)
            )
        )

        XCTAssertTrue(coordinator.hasActivePresentation)
        XCTAssertNotNil(coordinator.studioLightPopover)

        coordinator.present(
            NotchMenu(
                title: "Menu",
                anchor: .zero,
                items: []
            )
        )

        XCTAssertNil(coordinator.studioLightPopover)
        XCTAssertNotNil(coordinator.menu)
        coordinator.dismissAll()
        XCTAssertFalse(coordinator.hasActivePresentation)
    }
}

private extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
