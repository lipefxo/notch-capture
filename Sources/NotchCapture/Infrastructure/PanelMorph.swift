import CoreGraphics
import SwiftUI

/// Pure geometry for a surface that grows from, and returns to, a fixed point
/// along the top edge of a display.
struct PanelMorphGeometry: Equatable, Sendable {
    static let virtualNotchSize = CGSize(width: 156, height: 8)

    let topCenter: CGPoint
    let sourceSize: CGSize
    let targetSize: CGSize

    var sourceFrame: CGRect { topAnchoredFrame(for: sourceSize) }
    var targetFrame: CGRect { topAnchoredFrame(for: targetSize) }

    var canvasSize: CGSize {
        CGSize(
            width: max(sourceSize.width, targetSize.width),
            height: max(sourceSize.height, targetSize.height)
        )
    }

    var canvasFrame: CGRect { topAnchoredFrame(for: canvasSize) }

    func interpolatedFrame(progress: CGFloat) -> CGRect {
        let progress = min(1, max(0, progress))
        let size = CGSize(
            width: sourceSize.width + ((targetSize.width - sourceSize.width) * progress),
            height: sourceSize.height + ((targetSize.height - sourceSize.height) * progress)
        )
        return topAnchoredFrame(for: size)
    }

    private func topAnchoredFrame(for size: CGSize) -> CGRect {
        CGRect(
            x: topCenter.x - (size.width / 2),
            y: topCenter.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func notchAnchorSize(for geometry: NotchGeometry) -> CGSize {
        guard let notchRect = geometry.notchRect, geometry.safeAreaInsets.top > 0 else {
            return virtualNotchSize
        }
        return CGSize(
            width: notchRect.width,
            height: max(notchRect.height, geometry.safeAreaInsets.top)
        )
    }

    static func concealedAnchorSize(
        for geometry: NotchGeometry,
        targetSize: CGSize
    ) -> CGSize {
        let anchor = notchAnchorSize(for: geometry)
        return CGSize(
            width: min(anchor.width, targetSize.width),
            height: min(anchor.height, targetSize.height)
        )
    }
}

struct PanelMorphRequest: Equatable {
    enum Phase: Equatable {
        case prepared
        case active
        case settled
    }

    let generation: Int
    var phase: Phase
    let geometry: PanelMorphGeometry
    let targetState: PanelState
    let kind: PanelTransitionPolicy.Kind
    let spring: NotchSpringProfile?
    let fadeDuration: TimeInterval
    let shellDelay: TimeInterval
    let contentDelay: TimeInterval
    let reduceMotion: Bool
    let wasVisible: Bool

    var morphDuration: TimeInterval {
        spring?.perceptualDuration ?? fadeDuration
    }

    var totalDuration: TimeInterval {
        shellDelay + morphDuration
    }
}

/// Shared transition state. AppKit owns the panel canvas and lifecycle while
/// SwiftUI owns the visible chrome; the request keeps both on one generation.
@MainActor
final class PanelMorphCoordinator: ObservableObject {
    @Published private(set) var request: PanelMorphRequest?

    func prepare(_ request: PanelMorphRequest) {
        var request = request
        request.phase = .prepared
        self.request = request
    }

    func begin(_ request: PanelMorphRequest) {
        var request = request
        request.phase = .active
        self.request = request
    }

    func activate(generation: Int) {
        guard var request, request.generation == generation else { return }
        request.phase = .active
        self.request = request
    }

    func settle(generation: Int) {
        guard var request, request.generation == generation else { return }
        request.phase = .settled
        self.request = request
    }

    func cancel() {
        request = nil
    }
}
