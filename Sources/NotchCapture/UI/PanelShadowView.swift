import SwiftUI

/// Shadow-only chrome rendered in a separate, mouse-transparent AppKit panel.
/// The opaque fill is fully covered by the foreground surface; it gives
/// SwiftUI's shadow renderer an alpha mask without adding visible foreground
/// chrome outside the interactive panel.
struct PanelShadowView: View {
    @ObservedObject var presentation: PanelShadowPresentation
    @EnvironmentObject private var morphCoordinator: PanelMorphCoordinator
    @State private var metrics = Metrics.hidden

    var body: some View {
        ZStack(alignment: .top) {
            if metrics.isVisible {
                NotchHugShape(bottomRadius: metrics.bottomRadius)
                    .fill(NotchTheme.ink.opacity(0.985))
                    .shadow(
                        color: .black.opacity(metrics.shadowOpacity),
                        radius: metrics.shadowRadius,
                        y: metrics.shadowY
                    )
                    .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onAppear {
            if let request = morphCoordinator.request {
                update(for: request)
            } else {
                metrics = Metrics.resolve(state: presentation.state, size: presentation.size)
            }
        }
        .onChange(of: presentation.state) { _, _ in updateImmediatelyIfNeeded() }
        .onChange(of: presentation.size) { _, _ in updateImmediatelyIfNeeded() }
        .onChange(of: morphCoordinator.request) { _, request in
            guard let request else { return }
            update(for: request)
        }
        .accessibilityHidden(true)
    }

    private func updateImmediatelyIfNeeded() {
        guard !presentation.isTransitioning else { return }
        metrics = Metrics.resolve(state: presentation.state, size: presentation.size)
    }

    private func update(for request: PanelMorphRequest) {
        let target = Metrics.resolve(state: presentation.state, size: request.geometry.targetSize)
        switch request.phase {
        case .prepared:
            metrics = target.anchored(at: request.geometry.sourceSize)
        case .active:
            if request.kind == .expand, metrics.shadowOpacity == 0 {
                metrics = target.anchored(at: request.geometry.sourceSize)
            }
            if request.reduceMotion {
                withAnimation(NotchMotion.reducedMotion) { metrics = target }
            } else {
                withAnimation(request.spring?.animation ?? NotchMotion.content) { metrics = target }
            }
        case .settled:
            metrics = target
        }
    }

    private struct Metrics: Equatable {
        let size: CGSize
        let bottomRadius: CGFloat
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowY: CGFloat

        static let hidden = Self(size: .zero, bottomRadius: 0, shadowOpacity: 0, shadowRadius: 0, shadowY: 0)

        var isVisible: Bool { size.width > 0 && size.height > 0 }

        static func resolve(state: PanelState, size: CGSize) -> Self {
            guard state.isVisible else { return .hidden }
            let shadowed = PanelShadowApron.resolve(for: state) != .none
            return Self(
                size: size,
                bottomRadius: shadowed ? NotchTheme.surfaceBottomRadius : 16,
                shadowOpacity: shadowed ? 0.46 : 0,
                shadowRadius: shadowed ? 24 : 0,
                shadowY: shadowed ? 14 : 0
            )
        }

        func anchored(at size: CGSize) -> Self {
            Self(size: size, bottomRadius: min(bottomRadius, max(1, size.height / 2)), shadowOpacity: 0, shadowRadius: 8, shadowY: 0)
        }
    }
}
