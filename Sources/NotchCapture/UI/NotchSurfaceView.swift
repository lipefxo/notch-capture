import SwiftUI

struct SurfaceChromeMetrics: Equatable {
    let size: CGSize
    let bottomRadius: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    static func resolve(for state: AppViewModel.SurfaceState) -> Self? {
        switch state {
        case .dormant, .screenshot:
            nil
        case .collapsed:
            Self(
                size: CGSize(width: 178, height: 34),
                bottomRadius: 16,
                shadowOpacity: 0.36,
                shadowRadius: 16,
                shadowY: 8
            )
        case .confirmation:
            Self(
                size: CGSize(width: 280, height: 56),
                bottomRadius: 24,
                shadowOpacity: 0.46,
                shadowRadius: 24,
                shadowY: 14
            )
        case .expanded, .drop:
            Self(
                size: CGSize(width: NotchTheme.width, height: NotchTheme.maxHeight),
                bottomRadius: 22,
                shadowOpacity: 0.46,
                shadowRadius: 24,
                shadowY: 14
            )
        case .onboarding:
            Self(
                size: CGSize(width: NotchTheme.width, height: 500),
                bottomRadius: 24,
                shadowOpacity: 0.46,
                shadowRadius: 24,
                shadowY: 14
            )
        case .settings:
            Self(
                size: CGSize(width: NotchTheme.width, height: NotchTheme.maxHeight),
                bottomRadius: 24,
                shadowOpacity: 0.46,
                shadowRadius: 24,
                shadowY: 14
            )
        }
    }
}

struct NotchSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedState: AppViewModel.SurfaceState?
    @State private var chromeMetrics: SurfaceChromeMetrics?
    @State private var activeTransition: AnyTransition = .opacity

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _displayedState = State(
            initialValue: SurfaceChromeMetrics.resolve(for: viewModel.surfaceState) == nil
                ? nil
                : viewModel.surfaceState
        )
        _chromeMetrics = State(initialValue: SurfaceChromeMetrics.resolve(for: viewModel.surfaceState))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let displayedState, let metrics = chromeMetrics {
                ZStack(alignment: .top) {
                    NotchSurfaceBackground(
                        bottomRadius: metrics.bottomRadius,
                        shadowOpacity: metrics.shadowOpacity,
                        shadowRadius: metrics.shadowRadius,
                        shadowY: metrics.shadowY
                    )

                    surfaceContent(for: displayedState)
                        .id(contentIdentity(for: displayedState))
                        .transition(activeTransition)
                        .clipShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                }
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
                .contentShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onChange(of: viewModel.surfaceState) { oldState, newState in
            // AppKit owns the retreat to hidden states. Keeping the last visible
            // surface mounted prevents the shrinking panel from becoming empty.
            guard let newMetrics = SurfaceChromeMetrics.resolve(for: newState) else { return }

            if isDropOnlyTransition(from: oldState, to: newState) {
                displayedState = newState
                chromeMetrics = newMetrics
                return
            }

            if displayedState == newState {
                chromeMetrics = newMetrics
                return
            }

            let visibleOldState = displayedState ?? oldState
            activeTransition = transition(from: visibleOldState, to: newState)
            withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content) {
                displayedState = newState
            }
            withAnimation(reduceMotion ? NotchMotion.reducedMotion : chromeAnimation(
                from: visibleOldState,
                to: newState
            )) {
                chromeMetrics = newMetrics
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func surfaceContent(for state: AppViewModel.SurfaceState) -> some View {
        switch state {
        case .dormant, .screenshot:
            EmptyView()
        case .collapsed:
            CollapsedPillView(viewModel: viewModel)
        case .confirmation:
            ConfirmationView(viewModel: viewModel)
        case .expanded, .drop:
            ExpandedInboxView(viewModel: viewModel)
        case .onboarding:
            OnboardingView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }

    private func isDropOnlyTransition(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> Bool {
        (oldState == .expanded && newState == .drop)
            || (oldState == .drop && newState == .expanded)
    }

    private func contentIdentity(for state: AppViewModel.SurfaceState) -> String {
        switch state {
        case .expanded, .drop: "expanded"
        case .dormant: "dormant"
        case .collapsed: "collapsed"
        case .confirmation: "confirmation"
        case .screenshot: "screenshot"
        case .onboarding: "onboarding"
        case .settings: "settings"
        }
    }

    private func transition(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        if oldState == .expanded && newState == .settings {
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 12)),
                removal: .opacity.combined(with: .offset(x: -12))
            )
        }
        if oldState == .settings && newState == .expanded {
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: -12)),
                removal: .opacity.combined(with: .offset(x: 12))
            )
        }
        if newState == .confirmation {
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .opacity
            )
        }

        return .opacity.combined(with: .offset(y: -4))
    }

    private func chromeAnimation(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> Animation {
        guard let oldMetrics = SurfaceChromeMetrics.resolve(for: oldState),
              let newMetrics = SurfaceChromeMetrics.resolve(for: newState) else {
            return NotchMotion.content
        }
        let oldArea = oldMetrics.size.width * oldMetrics.size.height
        let newArea = newMetrics.size.width * newMetrics.size.height
        if newArea > oldArea { return NotchMotion.surfaceExpansion.animation }
        if newArea < oldArea { return NotchMotion.surfaceContraction.animation }
        return NotchMotion.content
    }
}

struct CollapsedPillView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHovered = false

    var body: some View {
        Button {
            viewModel.openExpanded()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
                Text("Capture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("⌃⇧N")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .frame(width: 178, height: 34)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isHovered ? NotchTheme.mint.opacity(0.65) : Color.white.opacity(0.1))
                    .frame(width: 38, height: 1)
                    .scaleEffect(x: isHovered ? 1 : 22 / 38)
                    .padding(.bottom, 3)
            }
            .contentShape(NotchHugShape(bottomRadius: 16))
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
        .notchHitTarget(NotchHugShape(bottomRadius: 16))
        .onHover { isHovered = $0 }
        .animation(NotchMotion.hover, value: isHovered)
        .help("Open Notch Capture")
        .accessibilityLabel("Open Notch Capture")
        .accessibilityHint("Opens the capture composer and inbox")
    }
}

struct ScreenshotStateView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NotchTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Select a region")
                    .font(.system(size: 13, weight: .semibold))
                Text("Drag anywhere on screen · Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer()
            Button("Cancel") { viewModel.dismiss() }
                .buttonStyle(CompactTextButtonStyle())
                .notchHitTarget(Rectangle())
                .foregroundStyle(NotchTheme.secondaryText)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(width: 360, height: 64)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Expanded") {
    NotchSurfaceView(viewModel: .preview)
        .padding(40)
        .background(Color.gray.opacity(0.35))
}

#Preview("Collapsed") {
    let model = AppViewModel.preview
    model.surfaceState = .collapsed
    return NotchSurfaceView(viewModel: model)
        .padding(40)
}
#endif
