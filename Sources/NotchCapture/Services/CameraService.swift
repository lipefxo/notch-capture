import AVFoundation
import Foundation

/// `AVCaptureSession` is not `Sendable`, but the session is only ever touched
/// on one serial queue, so handing it across that hop is safe by construction.
private struct UncheckedTransfer<Value>: @unchecked Sendable {
    let value: Value
}

/// Holds the capture session outside actor isolation. `AVCaptureSession` is not
/// `Sendable` and `startRunning()` blocks, so the session is only ever touched
/// on its own serial queue; keeping it here also lets `deinit` tear the input
/// down synchronously from any thread.
private final class CameraSessionLifetime: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lipe.notchcapture.camera")
    private var session: AVCaptureSession?

    /// The preview layer is created alongside the session so the SwiftUI layer
    /// host never has to reach for the session itself.
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func start(device: AVCaptureDevice) throws -> AVCaptureVideoPreviewLayer {
        if let previewLayer, session != nil { return previewLayer }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraServiceError.inputUnavailable
        }

        session.beginConfiguration()
        session.sessionPreset = Self.landscapePreset(for: device, in: session)
        session.addInput(input)
        session.commitConfiguration()

        let landscapeFormat = Self.landscapeFormat(for: device)
        Self.applyIfPortrait(landscapeFormat, to: device)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        // A mirror has to read like a mirror: without this the preview is the
        // camera's own (unflipped) view and every movement feels inverted.
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        self.session = session
        self.previewLayer = layer
        let transfer = UncheckedTransfer(value: (session: session, device: device, format: landscapeFormat))
        queue.async {
            transfer.value.session.startRunning()
            // A gimbal camera parked in portrait mode overrides the format that
            // was chosen before the stream opened, so landscape is asserted once
            // more with frames flowing — that is what rotates the gimbal back.
            Self.applyIfPortrait(transfer.value.format, to: transfer.value.device)
        }
        return layer
    }

    /// Only ever moves a camera that is currently portrait, so a webcam the user
    /// deliberately left in landscape is never reconfigured out from under them.
    private static func applyIfPortrait(_ format: AVCaptureDevice.Format?, to device: AVCaptureDevice) {
        guard let format else { return }
        let active = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard active.height > active.width else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    /// Gimbal webcams such as the Insta360 Link advertise portrait formats
    /// alongside landscape ones and physically rotate to match whichever format
    /// the session activates, so `.high` could stand the mirror on its side.
    /// These presets name their dimensions, which pins the camera to landscape.
    /// 720p is first on purpose: a 400pt preview gains nothing from more pixels
    /// and pays for them in power.
    private static let landscapePresets: [AVCaptureSession.Preset] = [
        .hd1280x720,
        .hd1920x1080,
        .vga640x480,
    ]

    private static func landscapePreset(
        for device: AVCaptureDevice,
        in session: AVCaptureSession
    ) -> AVCaptureSession.Preset {
        landscapePresets.first {
            device.supportsSessionPreset($0) && session.canSetSessionPreset($0)
        } ?? .high
    }

    /// The widest-supported format nearest 720p 16:9, which is what the preset
    /// list asks for too — the two must agree or the session resets the device.
    private static func landscapeFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let targetAspect = 16.0 / 9.0
        let preferredWidth = 1280.0

        return device.formats
            .map { ($0, CMVideoFormatDescriptionGetDimensions($0.formatDescription)) }
            .filter { $0.1.width >= $0.1.height }
            .min { lhs, rhs in
                let lhsAspect = abs(Double(lhs.1.width) / Double(lhs.1.height) - targetAspect)
                let rhsAspect = abs(Double(rhs.1.width) / Double(rhs.1.height) - targetAspect)
                guard abs(lhsAspect - rhsAspect) <= 0.01 else { return lhsAspect < rhsAspect }
                return abs(Double(lhs.1.width) - preferredWidth)
                    < abs(Double(rhs.1.width) - preferredWidth)
            }?
            .0
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        previewLayer = nil
        let transfer = UncheckedTransfer(value: session)
        queue.async {
            let session = transfer.value
            session.stopRunning()
            for input in session.inputs {
                session.removeInput(input)
            }
        }
    }
}

enum CameraServiceError: LocalizedError {
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "The camera could not be added to the capture session."
        }
    }
}

/// Owns the live camera preview behind the notch mirror surface. The service
/// publishes a coarse state rather than the session itself so the UI never has
/// to reason about AVFoundation.
@MainActor
final class CameraService {
    /// The running case carries its own preview layer so the UI never has to
    /// reach back into the service (or into AVFoundation) to find one.
    enum PreviewState: Equatable {
        case idle
        case requestingAccess
        case denied
        case unavailable
        case running(AVCaptureVideoPreviewLayer)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.requestingAccess, .requestingAccess),
                 (.denied, .denied),
                 (.unavailable, .unavailable):
                return true
            case let (.running(lhsLayer), .running(rhsLayer)):
                return lhsLayer === rhsLayer
            default:
                return false
            }
        }
    }

    private(set) var state: PreviewState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: (@MainActor (PreviewState) -> Void)?

    /// `AVCaptureDevice.uniqueID` of the camera behind the running preview.
    /// CoreMediaIO reports the same string, which is how `CameraControlService`
    /// finds the matching device without duplicating the selection rules.
    private(set) var activeDeviceUID: String?

    private let sessionLifetime = CameraSessionLifetime()
    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: (@escaping @Sendable (Bool) -> Void) -> Void
    private let resolveDevice: @MainActor () -> AVCaptureDevice?
    private let onAccessPrompt: () -> Void
    private var accessTask: Task<Void, Never>?

    init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        requestAccess: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        },
        resolveDevice: @escaping @MainActor () -> AVCaptureDevice? = CameraService.defaultDevice,
        onAccessPrompt: @escaping () -> Void = {}
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        self.resolveDevice = resolveDevice
        self.onAccessPrompt = onAccessPrompt
    }

    deinit {
        accessTask?.cancel()
        sessionLifetime.stop()
    }

    /// Continuity and external cameras are ordinary video devices on macOS 14,
    /// so the built-in FaceTime camera is simply the first match when present.
    static func defaultDevice() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
    }

    func start() {
        switch authorizationStatus() {
        case .authorized:
            activateSession()
        case .notDetermined:
            requestAuthorization()
        default:
            state = .denied
        }
    }

    func stop() {
        accessTask?.cancel()
        accessTask = nil
        sessionLifetime.stop()
        activeDeviceUID = nil
        state = .idle
    }

    private func requestAuthorization() {
        guard accessTask == nil else { return }
        state = .requestingAccess
        // The panel deliberately never becomes key, so without this the TCC
        // prompt can open behind whatever the user is working in.
        onAccessPrompt()
        accessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await withCheckedContinuation { continuation in
                self.requestAccess { granted in
                    continuation.resume(returning: granted)
                }
            }
            self.accessTask = nil
            guard !Task.isCancelled, self.state == .requestingAccess else { return }
            if granted {
                self.activateSession()
            } else {
                self.state = .denied
            }
        }
    }

    private func activateSession() {
        guard let device = resolveDevice() else {
            state = .unavailable
            return
        }
        do {
            let layer = try sessionLifetime.start(device: device)
            activeDeviceUID = device.uniqueID
            state = .running(layer)
        } catch {
            activeDeviceUID = nil
            state = .unavailable
        }
    }
}
