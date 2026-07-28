import AVFoundation
import AppKit
import SwiftUI

/// The webcam mirror. Unlike the inbox surfaces this one is meant to stay open
/// while the user works elsewhere, so it never takes focus and never dismisses
/// itself — the header close button and the pill toggle are the only exits.
struct MirrorSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel

    /// Where the gimbal was aiming when the current drag began, so the whole
    /// drag is one absolute move rather than an accumulation of deltas that
    /// would drift as the motor lags behind.
    @State private var dragOrigin: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
                .frame(
                    width: NotchTheme.mirrorPreviewWidth,
                    height: NotchTheme.mirrorPreviewHeight
                )
                .background(NotchTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NotchTheme.controlStroke)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .gesture(moveGesture)
                .help(viewModel.cameraControls.canMove ? "Drag to move the camera" : "")
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(width: NotchTheme.width, height: NotchTheme.mirrorHeight)
        .background(NotchTheme.graphite)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mirror")
    }

    /// 0.2° per point. The Link sees roughly 79° across a 400pt preview, so a
    /// drag moves the scene about as far as the pointer travelled — the image
    /// follows the cursor rather than sliding out from under it.
    private static let arcsecondsPerPoint: Double = 720

    /// The preview is mirrored, which flips the horizontal sense twice and so
    /// cancels out: dragging right really does want a rightward pan. Dragging
    /// down tilts up, the same way dragging a map downward reveals what is above.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard viewModel.cameraControls.canMove else { return }
                let origin = dragOrigin ?? CGPoint(x: viewModel.cameraPan, y: viewModel.cameraTilt)
                if dragOrigin == nil { dragOrigin = origin }
                // Zooming in narrows the field of view, so the same hand
                // movement should sweep proportionally less of the scene.
                let scale = Self.arcsecondsPerPoint / max(viewModel.cameraZoomFactor, 1)
                viewModel.moveCamera(
                    toPan: origin.x + (value.translation.width * scale),
                    tilt: origin.y + (value.translation.height * scale)
                )
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var header: some View {
        ZStack {
            // The physical notch sits in the middle of this row; tapping it is
            // the same "put it away" gesture the expanded surface offers.
            Button(action: viewModel.toggleMirror) {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(
                        width: max(0, viewModel.collapsedActivityLayout.notchWidth),
                        height: 54
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Close mirror")

            HStack(spacing: 10) {
                Text("Mirror")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                Spacer()
                cameraControls
                Button(action: viewModel.toggleMirror) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(PressableIconButtonStyle())
                .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("Close mirror")
                .accessibilityLabel("Close mirror")
            }
            .padding(.leading, 20)
            .padding(.trailing, 13)
        }
        .frame(height: 54)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    /// Only cameras that publish UVC controls get these; the built-in FaceTime
    /// camera publishes none, so the header stays a title and a close button.
    @ViewBuilder
    private var cameraControls: some View {
        // Capabilities are only populated while a device is streaming, so this
        // doubles as the "preview is live" check.
        if !viewModel.cameraControls.isEmpty {
            HStack(spacing: 2) {
                if viewModel.cameraControls.zoomRange != nil {
                    controlButton(
                        "minus.magnifyingglass",
                        label: "Zoom out",
                        isEnabled: viewModel.canZoomOut
                    ) {
                        viewModel.stepCameraZoom(by: -1)
                    }

                    // Monospaced design, not rounded+monospacedDigit: that pair
                    // resolves to no usable font here and renders as nothing.
                    Text(String(format: "%.1f×", viewModel.cameraZoomFactor))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .frame(width: 34)
                        .accessibilityLabel("Zoom \(String(format: "%.1f", viewModel.cameraZoomFactor)) times")
                        .accessibilityLabel("Zoom \(String(format: "%.1f", viewModel.cameraZoomFactor)) times")

                    controlButton(
                        "plus.magnifyingglass",
                        label: "Zoom in",
                        isEnabled: viewModel.canZoomIn
                    ) {
                        viewModel.stepCameraZoom(by: 1)
                    }
                }

                if viewModel.cameraControls.canRecenter {
                    controlButton("dot.scope", label: "Recenter camera", isEnabled: true) {
                        viewModel.recenterCamera()
                    }
                }
            }
        }
    }

    private func controlButton(
        _ icon: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(PressableIconButtonStyle(width: 24))
        .notchHitTarget(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var preview: some View {
        switch viewModel.cameraPreview {
        case let .running(layer):
            CameraPreviewLayerView(previewLayer: layer)
        case .requestingAccess:
            placeholder(
                icon: "camera.aperture",
                title: "Waiting for camera access",
                message: "Choose Allow in the system prompt to start the mirror."
            )
        case .denied:
            placeholder(
                icon: "lock",
                title: "Camera access is off",
                message: "Turn on Notch Capture under Privacy & Security → Camera.",
                action: ("Open System Settings", viewModel.hooks.onOpenCameraSettings)
            )
        case .unavailable:
            placeholder(
                icon: "camera.aperture",
                title: "No camera found",
                message: "Connect a camera, or use Continuity Camera from an iPhone."
            )
        case .idle:
            placeholder(icon: "camera.aperture", title: "Starting the camera", message: nil)
        }
    }

    private func placeholder(
        icon: String,
        title: String,
        message: String?,
        action: (title: String, perform: () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchTheme.tertiaryText)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
            if let message {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Hosts the capture preview layer. `AVCaptureVideoPreviewLayer` is a CALayer,
/// so it is added as a sublayer of a layer-backed view and resized by hand —
/// AppKit does not lay out manually inserted sublayers.
private struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.attach(previewLayer)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.attach(previewLayer)
    }
}

private final class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard self.previewLayer !== previewLayer else { return }
        self.previewLayer?.removeFromSuperlayer()
        self.previewLayer = previewLayer
        layer?.addSublayer(previewLayer)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // The preview must not animate its way to a new size while the panel
        // morphs open, or the first frames arrive letterboxed.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
