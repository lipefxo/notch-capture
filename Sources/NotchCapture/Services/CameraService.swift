import AVFoundation
import Foundation

/// `AVCaptureSession` is not `Sendable`, but the session is only ever touched
/// on one serial queue, so handing it across that hop is safe by construction.
private struct UncheckedTransfer<Value>: @unchecked Sendable {
    let value: Value
}

struct CameraFormatDimensions: Equatable, Sendable {
    let width: Int32
    let height: Int32
}

enum CameraLandscapePolicy {
    /// Returns the widest format nearest 720p 16:9. Keeping this selection pure
    /// makes the no-landscape fallback testable without camera hardware.
    static func preferredFormatIndex(in dimensions: [CameraFormatDimensions]) -> Int? {
        let targetAspect = 16.0 / 9.0
        let preferredWidth = 1280.0

        return dimensions.indices
            .filter { dimensions[$0].width >= dimensions[$0].height }
            .min { lhsIndex, rhsIndex in
                let lhs = dimensions[lhsIndex]
                let rhs = dimensions[rhsIndex]
                let lhsAspect = abs(Double(lhs.width) / Double(lhs.height) - targetAspect)
                let rhsAspect = abs(Double(rhs.width) / Double(rhs.height) - targetAspect)
                guard abs(lhsAspect - rhsAspect) <= 0.01 else { return lhsAspect < rhsAspect }
                return abs(Double(lhs.width) - preferredWidth)
                    < abs(Double(rhs.width) - preferredWidth)
            }
    }
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

    func start(
        device: AVCaptureDevice,
        completion: @escaping @Sendable (Result<AVCaptureVideoPreviewLayer, CameraServiceError>) -> Void
    ) throws {
        if let previewLayer, session != nil {
            completion(.success(previewLayer))
            return
        }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraServiceError.inputUnavailable
        }

        session.beginConfiguration()
        session.sessionPreset = Self.landscapePreset(for: device, in: session)
        session.addInput(input)
        let landscapeFormat = Self.landscapeFormat(for: device)
        Self.applyIfPortrait(landscapeFormat, to: device)
        session.commitConfiguration()

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
        let transfer = UncheckedTransfer(
            value: (
                session: session,
                device: device,
                format: landscapeFormat,
                layer: layer
            )
        )
        queue.async {
            transfer.value.session.startRunning()
            // A gimbal camera parked in portrait mode overrides the format that
            // was chosen before the stream opened, so landscape is asserted once
            // more with frames flowing. The layer is not published until this
            // completes, so portrait frames stay behind the starting placeholder.
            Self.applyIfPortrait(transfer.value.format, to: transfer.value.device)
            if transfer.value.format != nil, !Self.isLandscape(transfer.value.device) {
                completion(.failure(.landscapeUnavailable))
            } else {
                completion(.success(transfer.value.layer))
            }
        }
    }

    /// Only ever moves a camera that is currently portrait, so a webcam the user
    /// deliberately left in landscape is never reconfigured out from under them.
    private static func applyIfPortrait(_ format: AVCaptureDevice.Format?, to device: AVCaptureDevice) {
        guard let format else { return }
        guard !isLandscape(device) else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private static func isLandscape(_ device: AVCaptureDevice) -> Bool {
        let active = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return active.width >= active.height
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
        let dimensions = device.formats.map {
            let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return CameraFormatDimensions(width: size.width, height: size.height)
        }
        guard let index = CameraLandscapePolicy.preferredFormatIndex(in: dimensions) else {
            return nil
        }
        return device.formats[index]
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
    case landscapeUnavailable

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "The camera could not be added to the capture session."
        case .landscapeUnavailable:
            return "The camera could not be prepared in landscape orientation."
        }
    }
}

/// Owns the live camera preview behind the notch mirror surface. The service
/// publishes a coarse state rather than the session itself so the UI never has
/// to reason about AVFoundation.
@MainActor
final class CameraService {
    struct RunningSession: @unchecked Sendable {
        let deviceUID: String
        let previewLayer: AVCaptureVideoPreviewLayer
    }

    typealias SessionStarter = (
        @escaping @Sendable (Result<RunningSession, CameraServiceError>) -> Void
    ) throws -> Void
    typealias SessionStopper = @Sendable () -> Void

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

    private let startSession: SessionStarter
    private let stopSession: SessionStopper
    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: (@escaping @Sendable (Bool) -> Void) -> Void
    private let onAccessPrompt: () -> Void
    private var accessTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var isStartingSession = false

    init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        requestAccess: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        },
        resolveDevice: @escaping @MainActor () -> AVCaptureDevice? = CameraService.defaultDevice,
        onAccessPrompt: @escaping () -> Void = {},
        startSession: SessionStarter? = nil,
        stopSession: SessionStopper? = nil
    ) {
        let sessionLifetime = CameraSessionLifetime()
        self.startSession = startSession ?? { completion in
            guard let device = resolveDevice() else {
                completion(.failure(.inputUnavailable))
                return
            }
            let deviceUID = device.uniqueID
            try sessionLifetime.start(device: device) { result in
                completion(result.map {
                    RunningSession(deviceUID: deviceUID, previewLayer: $0)
                })
            }
        }
        self.stopSession = stopSession ?? {
            sessionLifetime.stop()
        }
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        self.onAccessPrompt = onAccessPrompt
    }

    deinit {
        accessTask?.cancel()
        stopSession()
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
        guard !isStartingSession else { return }
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
        sessionGeneration += 1
        isStartingSession = false
        accessTask?.cancel()
        accessTask = nil
        stopSession()
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
        guard !isStartingSession else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        isStartingSession = true
        do {
            try startSession { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.isStartingSession = false
                    switch result {
                    case let .success(session):
                        self.activeDeviceUID = session.deviceUID
                        self.state = .running(session.previewLayer)
                    case .failure:
                        self.stopSession()
                        self.activeDeviceUID = nil
                        self.state = .unavailable
                    }
                }
            }
        } catch {
            isStartingSession = false
            activeDeviceUID = nil
            state = .unavailable
        }
    }
}
