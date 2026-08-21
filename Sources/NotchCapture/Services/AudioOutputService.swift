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
    func setVolume(_ volume: Double) throws
    func setMuted(_ isMuted: Bool) throws
}

@MainActor
protocol CoreAudioHardwareAccessing: AnyObject {
    var onChange: (@MainActor () -> Void)? { get set }

    func devices() throws -> [AudioOutputDevice]
    func defaultOutputDeviceID() throws -> UInt32?
    func defaultSystemOutputDeviceID() throws -> UInt32?
    func setDefaultOutputDeviceID(_ id: UInt32) throws
    func setDefaultSystemOutputDeviceID(_ id: UInt32) throws
    func volumeState(for deviceID: UInt32) throws -> AudioVolumeViewState
    func setVolume(_ volume: Double, for deviceID: UInt32) throws
    func setMuted(_ isMuted: Bool, for deviceID: UInt32) throws
    func observeVolumeAndMute(on deviceID: UInt32?) throws
    func startObserving() throws
    func stopObserving()
}

enum AudioOutputServiceError: LocalizedError, Equatable {
    case unavailable(AudioOutputTarget)
    case switchFailed(AudioOutputTarget, String)
    case volumeUnavailable(String?)
    case muteUnavailable(String?)
    case volumeChangeFailed(String)
    case muteChangeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(target):
            "\(target.displayName) isn’t connected."
        case let .switchFailed(target, reason):
            "Couldn’t switch audio to \(target.displayName). \(reason)"
        case let .volumeUnavailable(deviceName):
            deviceName.map { "\($0) uses its own volume controls." }
                ?? "The current output uses its own volume controls."
        case let .muteUnavailable(deviceName):
            deviceName.map { "\($0) doesn’t expose a software mute control." }
                ?? "The current output doesn’t expose a software mute control."
        case let .volumeChangeFailed(reason):
            "Couldn’t change output volume. \(reason)"
        case let .muteChangeFailed(reason):
            "Couldn’t change output mute. \(reason)"
        }
    }
}

@MainActor
final class AudioOutputService: AudioOutputControlling {
    private struct ResolvedState {
        let viewState: AudioOutputViewState
        let outputDeviceID: UInt32?
    }

    private let hardware: any CoreAudioHardwareAccessing
    private var outputDeviceID: UInt32?
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
        guard let resolved = try? makeState() else { return }
        adopt(resolved)
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

        let refreshed: ResolvedState
        do {
            refreshed = try makeState()
        } catch {
            throw AudioOutputServiceError.switchFailed(target, error.localizedDescription)
        }
        adopt(refreshed)
    }

    func setVolume(_ volume: Double) throws {
        guard let outputDeviceID, state.volume.canSetVolume else {
            throw AudioOutputServiceError.volumeUnavailable(state.volume.deviceName)
        }
        do {
            try hardware.setVolume(min(1, max(0, volume)), for: outputDeviceID)
            adopt(try makeState())
        } catch let error as AudioOutputServiceError {
            throw error
        } catch {
            refresh()
            throw AudioOutputServiceError.volumeChangeFailed(error.localizedDescription)
        }
    }

    func setMuted(_ isMuted: Bool) throws {
        guard let outputDeviceID, state.volume.canSetMute else {
            throw AudioOutputServiceError.muteUnavailable(state.volume.deviceName)
        }
        do {
            try hardware.setMuted(isMuted, for: outputDeviceID)
            adopt(try makeState())
        } catch let error as AudioOutputServiceError {
            throw error
        } catch {
            refresh()
            throw AudioOutputServiceError.muteChangeFailed(error.localizedDescription)
        }
    }

    private func makeState() throws -> ResolvedState {
        let devices = try hardware.devices()
        let selectable = devices.filter(\.isSelectable)
        let targetDevices = Dictionary(uniqueKeysWithValues: AudioOutputTarget.allCases.compactMap { target in
            selectable.first(where: { target.matches(deviceName: $0.name) }).map { (target, $0) }
        })
        let mediaID = try hardware.defaultOutputDeviceID()
        let systemID = try hardware.defaultSystemOutputDeviceID()
        let mediaDevice = mediaID.flatMap { id in devices.first(where: { $0.id == id }) }
        let systemDevice = systemID.flatMap { id in devices.first(where: { $0.id == id }) }
        var volumeState = mediaID.flatMap { try? hardware.volumeState(for: $0) } ?? .empty
        volumeState.deviceName = mediaDevice?.name

        return ResolvedState(
            viewState: AudioOutputViewState(
                availableTargets: Set(targetDevices.keys),
                mediaTarget: mediaDevice.flatMap(Self.target(for:)),
                systemTarget: systemDevice.flatMap(Self.target(for:)),
                mediaDeviceName: mediaDevice?.name,
                systemDeviceName: systemDevice?.name,
                volume: volumeState
            ),
            outputDeviceID: mediaID
        )
    }

    private static func target(for device: AudioOutputDevice) -> AudioOutputTarget? {
        AudioOutputTarget.allCases.first(where: { $0.matches(deviceName: device.name) })
    }

    private func publish(_ newState: AudioOutputViewState) {
        state = newState
        onChange?(newState)
    }

    private func adopt(_ resolved: ResolvedState) {
        outputDeviceID = resolved.outputDeviceID
        try? hardware.observeVolumeAndMute(on: resolved.outputDeviceID)
        publish(resolved.viewState)
    }
}

struct CoreAudioHardwareError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "\(operation) failed (Core Audio status \(status))."
    }
}

enum AudioVolumeChannelScaling {
    static func values(
        preservingBalance currentValues: [Float32],
        target: Float32
    ) -> [Float32] {
        let clampedTarget = min(1, max(0, target))
        guard let currentMaximum = currentValues.max(), currentMaximum > 0 else {
            return currentValues.map { _ in clampedTarget }
        }
        return currentValues.map { current in
            min(1, max(0, clampedTarget * (current / currentMaximum)))
        }
    }
}

@MainActor
final class CoreAudioHardwareBackend: CoreAudioHardwareAccessing, @unchecked Sendable {
    private struct Observation {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
    }

    var onChange: (@MainActor () -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var observations: [Observation] = []
    private var observedDeviceID: AudioObjectID?
    private var desiredDeviceID: AudioObjectID?
    private var isObserving = false

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

    func volumeState(for deviceID: UInt32) throws -> AudioVolumeViewState {
        let object = AudioObjectID(deviceID)
        let volumeAddresses = controlAddresses(
            for: object,
            selector: kAudioDevicePropertyVolumeScalar
        )
        let muteAddresses = controlAddresses(
            for: object,
            selector: kAudioDevicePropertyMute
        )
        let volumes = volumeAddresses.compactMap { try? float32Property(object, address: $0) }
        let muteValues = muteAddresses.compactMap { try? uint32Property(object, address: $0) }

        return AudioVolumeViewState(
            value: volumes.max().map(Double.init),
            isMuted: !muteValues.isEmpty && muteValues.allSatisfy { $0 != 0 },
            canSetVolume: volumeAddresses.contains { isPropertySettable(object, address: $0) },
            canSetMute: muteAddresses.contains { isPropertySettable(object, address: $0) },
            deviceName: nil
        )
    }

    func setVolume(_ volume: Double, for deviceID: UInt32) throws {
        let object = AudioObjectID(deviceID)
        let addresses = controlAddresses(
            for: object,
            selector: kAudioDevicePropertyVolumeScalar
        ).filter { isPropertySettable(object, address: $0) }
        guard !addresses.isEmpty else {
            throw CoreAudioHardwareError(
                operation: "Set output volume",
                status: kAudioHardwareUnsupportedOperationError
            )
        }

        let target = Float32(min(1, max(0, volume)))
        if addresses.count == 1, addresses[0].mElement == kAudioObjectPropertyElementMain {
            try setFloat32Property(object, address: addresses[0], value: target)
            return
        }

        let existing = addresses.map { (try? float32Property(object, address: $0)) ?? 0 }
        let balancedValues = AudioVolumeChannelScaling.values(
            preservingBalance: existing,
            target: target
        )
        for (index, address) in addresses.enumerated() {
            let balancedValue = balancedValues[index]
            try setFloat32Property(object, address: address, value: balancedValue)
        }
    }

    func setMuted(_ isMuted: Bool, for deviceID: UInt32) throws {
        let object = AudioObjectID(deviceID)
        let addresses = controlAddresses(
            for: object,
            selector: kAudioDevicePropertyMute
        ).filter { isPropertySettable(object, address: $0) }
        guard !addresses.isEmpty else {
            throw CoreAudioHardwareError(
                operation: "Set output mute",
                status: kAudioHardwareUnsupportedOperationError
            )
        }
        for address in addresses {
            try setUInt32Property(object, address: address, value: isMuted ? 1 : 0)
        }
    }

    func observeVolumeAndMute(on deviceID: UInt32?) throws {
        desiredDeviceID = deviceID.map { AudioObjectID($0) }
        guard isObserving, desiredDeviceID != observedDeviceID else { return }
        try replaceDeviceObservations()
    }

    func startObserving() throws {
        guard !isObserving else { return }
        isObserving = true
        let addresses = [
            Self.address(kAudioHardwarePropertyDevices),
            Self.address(kAudioHardwarePropertyDefaultOutputDevice),
            Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice),
        ]
        do {
            for address in addresses { try addObservation(object: systemObject, address: address) }
            try replaceDeviceObservations()
        } catch {
            stopObserving()
            throw error
        }
    }

    func stopObserving() {
        for observation in observations {
            var address = observation.address
            AudioObjectRemovePropertyListener(
                observation.object,
                &address,
                Self.propertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        observations.removeAll()
        observedDeviceID = nil
        isObserving = false
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
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func addObservation(
        object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress
    ) throws {
        var address = sourceAddress
        try check(
            AudioObjectAddPropertyListener(
                object,
                &address,
                Self.propertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            ),
            operation: "Observe audio output"
        )
        observations.append(Observation(object: object, address: sourceAddress))
    }

    private func replaceDeviceObservations() throws {
        let retained = observations.filter { $0.object == systemObject }
        for observation in observations where observation.object != systemObject {
            var address = observation.address
            AudioObjectRemovePropertyListener(
                observation.object,
                &address,
                Self.propertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        observations = retained
        observedDeviceID = desiredDeviceID
        guard let deviceID = observedDeviceID else { return }

        let addresses = controlAddresses(
            for: deviceID,
            selector: kAudioDevicePropertyVolumeScalar
        ) + controlAddresses(
            for: deviceID,
            selector: kAudioDevicePropertyMute
        )
        do {
            for address in addresses {
                try addObservation(object: deviceID, address: address)
            }
        } catch {
            self.observedDeviceID = nil
            throw error
        }
    }

    private func controlAddresses(
        for object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyAddress] {
        let main = Self.address(
            selector,
            scope: kAudioDevicePropertyScopeOutput
        )
        let hasMain = hasProperty(object, address: main)
        if hasMain, isPropertySettable(object, address: main) { return [main] }

        let channels = (1...32).compactMap { element in
            let address = Self.address(
                selector,
                scope: kAudioDevicePropertyScopeOutput,
                element: AudioObjectPropertyElement(element)
            )
            return hasProperty(object, address: address) ? address : nil
        }
        if channels.contains(where: { isPropertySettable(object, address: $0) }) {
            return channels
        }
        return hasMain ? [main] : channels
    }

    private func hasProperty(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress
    ) -> Bool {
        var address = sourceAddress
        return AudioObjectHasProperty(object, &address)
    }

    private func isPropertySettable(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress
    ) -> Bool {
        var address = sourceAddress
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr
            && settable.boolValue
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
        try uint32Property(object, address: Self.address(selector, scope: scope))
    }

    private func uint32Property(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress
    ) throws -> UInt32 {
        var address = sourceAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value),
            operation: "Read audio hardware property"
        )
        return value
    }

    private func float32Property(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress
    ) throws -> Float32 {
        var address = sourceAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try check(
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value),
            operation: "Read output volume"
        )
        return value
    }

    private func setFloat32Property(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress,
        value sourceValue: Float32
    ) throws {
        var address = sourceAddress
        var value = sourceValue
        try check(
            AudioObjectSetPropertyData(
                object,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &value
            ),
            operation: "Set output volume"
        )
    }

    private func setUInt32Property(
        _ object: AudioObjectID,
        address sourceAddress: AudioObjectPropertyAddress,
        value sourceValue: UInt32
    ) throws {
        var address = sourceAddress
        var value = sourceValue
        try check(
            AudioObjectSetPropertyData(
                object,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            ),
            operation: "Set output mute"
        )
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
