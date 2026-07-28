import CoreMediaIO
import Foundation

enum CameraPanTiltRestorePolicy {
    /// The Link quantises pan/tilt to whole degrees. If its native register still
    /// contains the saved target after Privacy Mode physically parked the
    /// gimbal, writing that same target again is ignored. Move the register one
    /// degree first so the real restore is a fresh command.
    static let primingStep: Double = 3600

    static func primingAim(
        current: CameraAim,
        target: CameraAim,
        panRange: ClosedRange<Double>,
        tiltRange: ClosedRange<Double>
    ) -> CameraAim? {
        guard current == target else { return nil }

        if let alternatePan = alternateValue(for: target.pan, in: panRange) {
            return CameraAim(pan: alternatePan, tilt: target.tilt)
        }
        if let alternateTilt = alternateValue(for: target.tilt, in: tiltRange) {
            return CameraAim(pan: target.pan, tilt: alternateTilt)
        }
        return nil
    }

    private static func alternateValue(
        for value: Double,
        in range: ClosedRange<Double>
    ) -> Double? {
        let upward = min(value + primingStep, range.upperBound)
        if upward != value { return upward }
        let downward = max(value - primingStep, range.lowerBound)
        return downward != value ? downward : nil
    }
}

/// Zoom and framing for cameras that publish UVC controls.
///
/// AVFoundation exposes none of this on macOS — an external camera reports a
/// maximum zoom factor of 1 and no pan/tilt at all. The controls live one layer
/// down, as child objects of the CoreMediaIO device, published by the system's
/// UVC assistant. Cameras that publish nothing (the built-in FaceTime camera,
/// for one) simply resolve to empty capabilities.
@MainActor
final class CameraControlService {
    struct Capabilities: Equatable, Sendable {
        var zoomRange: ClosedRange<Double>?
        var canRecenter = false
        /// Both in arcseconds, the gimbal's own units.
        var panRange: ClosedRange<Double>?
        var tiltRange: ClosedRange<Double>?

        static let none = Self()

        var canMove: Bool { panRange != nil && tiltRange != nil }
        var isEmpty: Bool { zoomRange == nil && !canRecenter }
    }

    private(set) var capabilities: Capabilities = .none

    private var zoomControl: CMIOObjectID?
    private var panTiltControl: CMIOObjectID?

    /// `deviceUID` is `AVCaptureDevice.uniqueID`, which is the same string
    /// CoreMediaIO reports for `kCMIODevicePropertyDeviceUID`.
    func attach(deviceUID: String) {
        detach()
        guard let device = Self.device(uid: deviceUID) else { return }

        let controls = Self.ownedObjects(of: device)
        zoomControl = controls.first { Self.classID(of: $0) == kCMIOZoomControlClassID }
        panTiltControl = controls.first { Self.classID(of: $0) == kCMIOPanTiltAbsoluteControlClassID }

        let travel = panTiltControl.flatMap(Self.panTiltRange(of:))
        capabilities = Capabilities(
            zoomRange: zoomControl.flatMap(Self.zoomRange(of:)),
            canRecenter: panTiltControl != nil,
            panRange: travel?.pan,
            tiltRange: travel?.tilt
        )
    }

    func detach() {
        zoomControl = nil
        panTiltControl = nil
        capabilities = .none
    }

    /// The device's own scale, where 100 is 1x. Reported as-is so the caller can
    /// keep the range and the value in the same units.
    var zoom: Double? {
        guard let zoomControl else { return nil }
        return Self.readFloat(zoomControl).map(Double.init)
    }

    func setZoom(_ value: Double) {
        guard let zoomControl, let range = capabilities.zoomRange else { return }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        Self.write(zoomControl, Float32(clamped))
    }

    /// The gimbal's current aim in arcseconds.
    var panTilt: (pan: Double, tilt: Double)? {
        guard let panTiltControl else { return nil }
        let bytes = Self.read(panTiltControl, kCMIOFeatureControlPropertyNativeValue)
        guard bytes.count >= 8 else { return nil }
        return (Double(Self.int32(bytes, 0)), Double(Self.int32(bytes, 4)))
    }

    /// Pan and tilt travel together as one eight-byte pair, so both axes are
    /// always written at once — there is no way to aim a single axis.
    func setPanTilt(pan: Double, tilt: Double) {
        guard let panTiltControl else { return }
        let clampedPan = capabilities.panRange.map { min(max(pan, $0.lowerBound), $0.upperBound) } ?? pan
        let clampedTilt = capabilities.tiltRange.map { min(max(tilt, $0.lowerBound), $0.upperBound) } ?? tilt
        var payload = withUnsafeBytes(of: Int32(clampedPan.rounded())) { Array($0) }
        payload.append(contentsOf: withUnsafeBytes(of: Int32(clampedTilt.rounded())) { Array($0) })
        Self.write(panTiltControl, bytes: payload)
    }

    /// Primes a parked gimbal only when its native register already equals the
    /// desired target. Returns true when the caller should briefly wait before
    /// issuing the real restore command.
    @discardableResult
    func primePanTiltRestore(pan: Double, tilt: Double) -> Bool {
        guard let current = panTilt,
              let panRange = capabilities.panRange,
              let tiltRange = capabilities.tiltRange else { return false }
        let target = CameraAim(
            pan: min(max(pan.rounded(), panRange.lowerBound), panRange.upperBound),
            tilt: min(max(tilt.rounded(), tiltRange.lowerBound), tiltRange.upperBound)
        )
        guard let primingAim = CameraPanTiltRestorePolicy.primingAim(
            current: CameraAim(pan: current.pan, tilt: current.tilt),
            target: target,
            panRange: panRange,
            tiltRange: tiltRange
        ) else { return false }
        setPanTilt(pan: primingAim.pan, tilt: primingAim.tilt)
        return true
    }

    /// Returns the gimbal to dead centre.
    func recenter() {
        setPanTilt(pan: 0, tilt: 0)
    }
}

// MARK: - CoreMediaIO plumbing

private extension CameraControlService {
    static func address(
        _ selector: Int,
        scope: Int = kCMIOObjectPropertyScopeGlobal
    ) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(scope),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func dataSize(_ object: CMIOObjectID, _ address: inout CMIOObjectPropertyAddress) -> UInt32 {
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    static func device(uid: String) -> CMIOObjectID? {
        var address = address(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        let size = dataSize(system, &address)
        guard size > 0 else { return nil }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else {
            return nil
        }
        return devices.first { string($0, kCMIODevicePropertyDeviceUID) == uid }
    }

    static func string(_ object: CMIOObjectID, _ selector: Int) -> String? {
        var address = address(selector)
        let size = dataSize(object, &address)
        guard size > 0 else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func ownedObjects(of device: CMIOObjectID) -> [CMIOObjectID] {
        var address = address(kCMIOObjectPropertyOwnedObjects, scope: kCMIODevicePropertyScopeInput)
        let size = dataSize(device, &address)
        guard size > 0 else { return [] }
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &objects) == noErr else {
            return []
        }
        return objects.filter { $0 != 0 }
    }

    static func classID(of object: CMIOObjectID) -> Int {
        var address = address(kCMIOObjectPropertyClass)
        var value: CMIOClassID = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            object, &address, 0, nil, UInt32(MemoryLayout<CMIOClassID>.size), &used, &value
        ) == noErr else { return 0 }
        return Int(value)
    }

    static func zoomRange(of control: CMIOObjectID) -> ClosedRange<Double>? {
        var address = address(
            kCMIOFeatureControlPropertyNativeRange,
            scope: kCMIODevicePropertyScopeInput
        )
        let size = dataSize(control, &address)
        guard size >= UInt32(MemoryLayout<AudioValueRange>.size) else { return nil }
        var range = AudioValueRange()
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(control, &address, 0, nil, size, &used, &range) == noErr,
              range.mMinimum.isFinite, range.mMaximum.isFinite,
              range.mMaximum > range.mMinimum else { return nil }
        return range.mMinimum...range.mMaximum
    }

    /// Pan/tilt is the one control whose range is not an `AudioValueRange`: it
    /// arrives as sixteen bytes holding the minimum pair followed by the
    /// maximum pair, each pair being pan then tilt as `Int32` arcseconds.
    static func panTiltRange(
        of control: CMIOObjectID
    ) -> (pan: ClosedRange<Double>, tilt: ClosedRange<Double>)? {
        let bytes = read(control, kCMIOFeatureControlPropertyNativeRange)
        guard bytes.count >= 16 else { return nil }
        let minPan = Double(int32(bytes, 0))
        let minTilt = Double(int32(bytes, 4))
        let maxPan = Double(int32(bytes, 8))
        let maxTilt = Double(int32(bytes, 12))
        guard maxPan > minPan, maxTilt > minTilt else { return nil }
        return (minPan...maxPan, minTilt...maxTilt)
    }

    static func read(_ control: CMIOObjectID, _ selector: Int) -> [UInt8] {
        var address = address(selector, scope: kCMIODevicePropertyScopeInput)
        let size = dataSize(control, &address)
        guard size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(control, &address, 0, nil, size, &used, &buffer) == noErr else {
            return []
        }
        return buffer
    }

    static func int32(_ bytes: [UInt8], _ offset: Int) -> Int32 {
        bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
    }

    static func readFloat(_ control: CMIOObjectID) -> Float32? {
        var address = address(
            kCMIOFeatureControlPropertyNativeValue,
            scope: kCMIODevicePropertyScopeInput
        )
        let size = dataSize(control, &address)
        guard size == UInt32(MemoryLayout<Float32>.size) else { return nil }
        var value: Float32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(control, &address, 0, nil, size, &used, &value) == noErr else {
            return nil
        }
        return value
    }

    static func write(_ control: CMIOObjectID, _ value: Float32) {
        write(control, bytes: withUnsafeBytes(of: value) { Array($0) })
    }

    static func write(_ control: CMIOObjectID, bytes: [UInt8]) {
        var address = address(
            kCMIOFeatureControlPropertyNativeValue,
            scope: kCMIODevicePropertyScopeInput
        )
        var payload = bytes
        _ = CMIOObjectSetPropertyData(control, &address, 0, nil, UInt32(payload.count), &payload)
    }
}
