import CoreAudio
import Foundation

@MainActor
protocol AudioOutputControlling: AnyObject {
    var state: AudioOutputViewState { get }
    var onChange: (@MainActor (AudioOutputViewState) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
    func select(_ target: AudioOutputTarget) throws
}

@MainActor
protocol CoreAudioHardwareAccessing: AnyObject {
    var onChange: (@MainActor () -> Void)? { get set }

    func devices() throws -> [AudioOutputDevice]
    func defaultOutputDeviceID() throws -> UInt32?
    func defaultSystemOutputDeviceID() throws -> UInt32?
    func setDefaultOutputDeviceID(_ id: UInt32) throws
    func setDefaultSystemOutputDeviceID(_ id: UInt32) throws
    func startObserving() throws
    func stopObserving()
}

enum AudioOutputServiceError: LocalizedError, Equatable {
    case unavailable(AudioOutputTarget)
    case switchFailed(AudioOutputTarget, String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(target):
            "\(target.displayName) isn’t connected."
        case let .switchFailed(target, reason):
            "Couldn’t switch audio to \(target.displayName). \(reason)"
        }
    }
}

@MainActor
final class AudioOutputService: AudioOutputControlling {
    private let hardware: any CoreAudioHardwareAccessing
    private(set) var state: AudioOutputViewState = .empty
    var onChange: (@MainActor (AudioOutputViewState) -> Void)?

    init(hardware: (any CoreAudioHardwareAccessing)? = nil) {
        self.hardware = hardware ?? CoreAudioHardwareBackend()
        self.hardware.onChange = { [weak self] in
            self?.refresh()
        }
    }

    func start() {
        refresh()
        try? hardware.startObserving()
    }

    func stop() {
        hardware.stopObserving()
    }

    func refresh() {
        guard let refreshed = try? makeState() else { return }
        publish(refreshed)
    }

    func select(_ target: AudioOutputTarget) throws {
        let devices: [AudioOutputDevice]
        do {
            devices = try hardware.devices()
        } catch {
            throw AudioOutputServiceError.switchFailed(target, error.localizedDescription)
        }
        guard let device = devices.first(where: {
            $0.isSelectable && target.matches(deviceName: $0.name)
        }) else {
            refresh()
            throw AudioOutputServiceError.unavailable(target)
        }

        do {
            try hardware.setDefaultOutputDeviceID(device.id)
            try hardware.setDefaultSystemOutputDeviceID(device.id)
        } catch {
            refresh()
            throw AudioOutputServiceError.switchFailed(target, error.localizedDescription)
        }

        let refreshed: AudioOutputViewState
        do {
            refreshed = try makeState()
        } catch {
            throw AudioOutputServiceError.switchFailed(target, error.localizedDescription)
        }
        publish(refreshed)
    }

    private func makeState() throws -> AudioOutputViewState {
        let devices = try hardware.devices()
        let selectable = devices.filter(\.isSelectable)
        let targetDevices = Dictionary(uniqueKeysWithValues: AudioOutputTarget.allCases.compactMap { target in
            selectable.first(where: { target.matches(deviceName: $0.name) }).map { (target, $0) }
        })
        let mediaID = try hardware.defaultOutputDeviceID()
        let systemID = try hardware.defaultSystemOutputDeviceID()
        let mediaDevice = mediaID.flatMap { id in devices.first(where: { $0.id == id }) }
        let systemDevice = systemID.flatMap { id in devices.first(where: { $0.id == id }) }

        return AudioOutputViewState(
            availableTargets: Set(targetDevices.keys),
            mediaTarget: mediaDevice.flatMap(Self.target(for:)),
            systemTarget: systemDevice.flatMap(Self.target(for:)),
            mediaDeviceName: mediaDevice?.name,
            systemDeviceName: systemDevice?.name
        )
    }

    private static func target(for device: AudioOutputDevice) -> AudioOutputTarget? {
        AudioOutputTarget.allCases.first(where: { $0.matches(deviceName: device.name) })
    }

    private func publish(_ newState: AudioOutputViewState) {
        state = newState
        onChange?(newState)
    }
}

struct CoreAudioHardwareError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "\(operation) failed (Core Audio status \(status))."
    }
}

@MainActor
final class CoreAudioHardwareBackend: CoreAudioHardwareAccessing, @unchecked Sendable {
    var onChange: (@MainActor () -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var observedAddresses: [AudioObjectPropertyAddress] = []

    func devices() throws -> [AudioOutputDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        let size = try propertyDataSize(systemObject, address: &address, operation: "Read audio devices")
        guard size > 0 else { return [] }

        var ids = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        var used = size
        try check(
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &used, &ids),
            operation: "Read audio devices"
        )

        return ids.compactMap { id in
            guard id != kAudioObjectUnknown,
                  let name = try? stringProperty(id, selector: kAudioObjectPropertyName) else {
                return nil
            }
            return AudioOutputDevice(
                id: id,
                name: name,
                isAlive: (try? uint32Property(id, selector: kAudioDevicePropertyDeviceIsAlive)) == 1,
                hasOutput: hasOutputStreams(id),
                canBeDefault: (try? uint32Property(
                    id,
                    selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                    scope: kAudioDevicePropertyScopeOutput
                )) == 1,
                canBeSystemDefault: (try? uint32Property(
                    id,
                    selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
                    scope: kAudioDevicePropertyScopeOutput
                )) == 1
            )
        }
    }

    func defaultOutputDeviceID() throws -> UInt32? {
        try defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func defaultSystemOutputDeviceID() throws -> UInt32? {
        try defaultDeviceID(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    func setDefaultOutputDeviceID(_ id: UInt32) throws {
        try setDefaultDeviceID(id, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func setDefaultSystemOutputDeviceID(_ id: UInt32) throws {
        try setDefaultDeviceID(id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    func startObserving() throws {
        guard observedAddresses.isEmpty else { return }
        let addresses = [
            Self.address(kAudioHardwarePropertyDevices),
            Self.address(kAudioHardwarePropertyDefaultOutputDevice),
            Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice),
        ]
        do {
            for var address in addresses {
                try check(
                    AudioObjectAddPropertyListener(
                        systemObject,
                        &address,
                        Self.propertyListener,
                        Unmanaged.passUnretained(self).toOpaque()
                    ),
                    operation: "Observe audio output"
                )
                observedAddresses.append(address)
            }
        } catch {
            stopObserving()
            throw error
        }
    }

    func stopObserving() {
        for var address in observedAddresses {
            AudioObjectRemovePropertyListener(
                systemObject,
                &address,
                Self.propertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        observedAddresses.removeAll()
    }

    private static let propertyListener: AudioObjectPropertyListenerProc = {
        _, _, _, clientData in
        guard let clientData else { return noErr }
        let backend = Unmanaged<CoreAudioHardwareBackend>
            .fromOpaque(clientData)
            .takeUnretainedValue()
        DispatchQueue.main.async {
            backend.onChange?()
        }
        return noErr
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultDeviceID(
        selector: AudioObjectPropertySelector
    ) throws -> UInt32? {
        let value = try uint32Property(systemObject, selector: selector)
        return value == kAudioObjectUnknown ? nil : value
    }

    private func setDefaultDeviceID(
        _ id: UInt32,
        selector: AudioObjectPropertySelector
    ) throws {
        var address = Self.address(selector)
        var value = AudioObjectID(id)
        try check(
            AudioObjectSetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<AudioObjectID>.size),
                &value
            ),
            operation: "Set audio output"
        )
    }

    private func stringProperty(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = Self.address(selector)
        let size = try propertyDataSize(object, address: &address, operation: "Read audio device name")
        var value: Unmanaged<CFString>?
        var used = size
        try check(
            AudioObjectGetPropertyData(object, &address, 0, nil, &used, &value),
            operation: "Read audio device name"
        )
        guard let value else {
            throw CoreAudioHardwareError(operation: "Read audio device name", status: kAudioHardwareUnspecifiedError)
        }
        return value.takeRetainedValue() as String
    }

    private func uint32Property(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> UInt32 {
        var address = Self.address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value),
            operation: "Read audio hardware property"
        )
        return value
    }

    private func hasOutputStreams(_ device: AudioObjectID) -> Bool {
        var address = Self.address(
            kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        )
        guard let size = try? propertyDataSize(
            device,
            address: &address,
            operation: "Read audio output streams"
        ) else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func propertyDataSize(
        _ object: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        operation: String
    ) throws -> UInt32 {
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size),
            operation: operation
        )
        return size
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CoreAudioHardwareError(operation: operation, status: status)
        }
    }
}
