import Foundation

struct StudioLightDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    var rssi: Int?
}

enum StudioLightDiscoveryPolicy {
    private static let serviceIdentifiers = [
        "FEE9",
        "0000FEE900001000800000805F9B34FB",
    ]

    private static let modelIdentifiers = [
        "MOLUSG60",
        "ZYPL103",
        "PL103",
        "G60",
    ]

    static func matches(
        advertisedName: String?,
        peripheralName: String?,
        serviceUUIDs: [String]
    ) -> Bool {
        let normalizedServices = serviceUUIDs.map(normalize)
        if normalizedServices.contains(where: serviceIdentifiers.contains) {
            return true
        }

        return [advertisedName, peripheralName]
            .compactMap { $0 }
            .map(normalize)
            .contains { name in
                modelIdentifiers.contains { name.contains($0) }
            }
    }

    static func displayName(
        advertisedName: String?,
        peripheralName: String?
    ) -> String {
        [advertisedName, peripheralName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? "Possible MOLUS G60"
    }

    private static func normalize(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}

struct StudioLightSnapshot: Equatable, Sendable {
    var isOn: Bool
    var brightness: Double
    var colorTemperature: Int

    static let initial = StudioLightSnapshot(
        isOn: false,
        brightness: 50,
        colorTemperature: 4_300
    )
}

enum StudioLightConnectionState: Equatable, Sendable {
    case notConfigured
    case bluetoothOff
    case permissionDenied
    case scanning
    case connecting
    case connected
    case disconnected(String)
    case notFound
    case unsupported(String)

    var statusText: String {
        switch self {
        case .notConfigured:
            "Not paired"
        case .bluetoothOff:
            "Bluetooth is off"
        case .permissionDenied:
            "Bluetooth access denied"
        case .scanning:
            "Looking for nearby lights…"
        case .connecting:
            "Connecting…"
        case .connected:
            "Connected"
        case let .disconnected(message):
            message
        case .notFound:
            "Light not found"
        case let .unsupported(message):
            message
        }
    }

    var isConnected: Bool {
        switch self {
        case .connected:
            true
        default:
            false
        }
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting:
            true
        default:
            false
        }
    }

    var canRetry: Bool {
        switch self {
        case .bluetoothOff, .permissionDenied, .connecting, .scanning, .notConfigured:
            false
        case .connected, .disconnected, .notFound, .unsupported:
            true
        }
    }
}

struct StudioLightViewState: Equatable, Sendable {
    var connection: StudioLightConnectionState
    var configuredDevice: StudioLightDevice?
    var discoveredDevices: [StudioLightDevice]
    var snapshot: StudioLightSnapshot

    static let empty = StudioLightViewState(
        connection: .notConfigured,
        configuredDevice: nil,
        discoveredDevices: [],
        snapshot: .initial
    )

    var controlsEnabled: Bool { connection.isConnected }
    var isConfigured: Bool { configuredDevice != nil }
}
