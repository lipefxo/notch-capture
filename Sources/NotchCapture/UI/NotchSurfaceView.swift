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

    func replacing(size: CGSize) -> Self {
        Self(
            size: size,
            bottomRadius: bottomRadius,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }

    func anchored(at size: CGSize) -> Self {
        Self(
            size: size,
            bottomRadius: min(bottomRadius, max(1, size.height / 2)),
            shadowOpacity: 0,
            shadowRadius: 8,
            shadowY: 0
        )
    }
}

struct NotchSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var morphCoordinator: PanelMorphCoordinator
    @StateObject private var presentation = NotchPresentationCoordinator()
    @State private var displayedState: AppViewModel.SurfaceState?
    @State private var chromeMetrics: SurfaceChromeMetrics?
    @State private var activeTransition: AnyTransition = .opacity
    @State private var surfaceOpacity = 1.0
    @State private var contentOpacity = 1.0
    @State private var contentOffsetY: CGFloat = 0
    @State private var morphTask: Task<Void, Never>?

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

                    ZStack {
                        surfaceContent(for: displayedState)
                            .id(contentIdentity(for: displayedState))
                            .transition(activeTransition)
                            .disabled(presentation.hasModal)
                            .accessibilityHidden(presentation.hasModal)

                        NotchPresentationLayer()
                    }
                    .environmentObject(presentation)
                    .clipShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                    .opacity(contentOpacity)
                    .offset(y: contentOffsetY)
                }
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
                .contentShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                .opacity(surfaceOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onChange(of: viewModel.surfaceState) { oldState, newState in
            handleSurfaceStateChange(from: oldState, to: newState)
        }
        .onChange(of: morphCoordinator.request) { _, request in
            guard let request else { return }
            handleMorphRequest(request)
        }
        .onDisappear {
            morphTask?.cancel()
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

    private func handleSurfaceStateChange(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) {
        if newState != .expanded && newState != .settings && newState != .onboarding {
            presentation.dismissAll()
        }

        guard let newMetrics = SurfaceChromeMetrics.resolve(for: newState) else {
            // The morph coordinator keeps the last visible shell mounted while
            // AppKit completes the retreat into the notch.
            return
        }
        if isDropOnlyTransition(from: oldState, to: newState) {
            morphTask?.cancel()
            displayedState = newState
            chromeMetrics = newMetrics
            surfaceOpacity = 1
            contentOpacity = 1
            contentOffsetY = 0
            return
        }

        guard let oldMetrics = SurfaceChromeMetrics.resolve(for: oldState),
              oldMetrics.size == newMetrics.size else {
            // Size-changing transitions are staged by PanelMorphCoordinator.
            return
        }
        if displayedState == newState {
            chromeMetrics = newMetrics
            return
        }

        morphTask?.cancel()
        let visibleOldState = displayedState ?? oldState
        activeTransition = transition(from: visibleOldState, to: newState)
        withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content) {
            displayedState = newState
            chromeMetrics = newMetrics
            surfaceOpacity = 1
            contentOpacity = 1
            contentOffsetY = 0
        }
    }

    private func handleMorphRequest(_ request: PanelMorphRequest) {
        switch request.phase {
        case .prepared:
            prepareMorph(request)
        case .active:
            beginMorph(request)
        case .settled:
            break
        }
    }

    private func prepareMorph(_ request: PanelMorphRequest) {
        morphTask?.cancel()
        guard request.targetState.isVisible,
              let targetMetrics = targetMetrics(for: request) else { return }
        withoutAnimation {
            activeTransition = .opacity
            displayedState = viewModel.surfaceState
            chromeMetrics = targetMetrics.anchored(at: request.geometry.sourceSize)
            surfaceOpacity = 1
            contentOpacity = 0
            contentOffsetY = -4
        }
    }

    private func beginMorph(_ request: PanelMorphRequest) {
        morphTask?.cancel()
        if request.reduceMotion {
            beginReducedMotionTransition(request)
            return
        }

        switch request.kind {
        case .expand:
            beginExpansion(request)
        case .contract, .hide:
            beginContraction(request)
        case .reducedFade, .immediate:
            break
        }
    }

    private func beginExpansion(_ request: PanelMorphRequest) {
        guard request.targetState.isVisible,
              let targetMetrics = targetMetrics(for: request) else { return }

        withoutAnimation {
            activeTransition = .opacity
            displayedState = viewModel.surfaceState
            if chromeMetrics == nil {
                chromeMetrics = targetMetrics.anchored(at: request.geometry.sourceSize)
            }
            surfaceOpacity = 1
            contentOpacity = 0
            contentOffsetY = -4
        }
        withAnimation(request.spring?.animation ?? NotchMotion.content) {
            chromeMetrics = targetMetrics
        }

        morphTask = Task { @MainActor in
            if request.contentDelay > 0 {
                try? await Task.sleep(for: .seconds(request.contentDelay))
            }
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }
            withAnimation(NotchMotion.insertion) {
                contentOpacity = 1
                contentOffsetY = 0
            }
        }
    }

    private func beginContraction(_ request: PanelMorphRequest) {
        surfaceOpacity = 1
        withAnimation(NotchMotion.removal) {
            contentOpacity = 0
            contentOffsetY = -4
        }

        morphTask = Task { @MainActor in
            if request.shellDelay > 0 {
                try? await Task.sleep(for: .seconds(request.shellDelay))
            }
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }

            let destinationMetrics: SurfaceChromeMetrics?
            if request.targetState.isVisible {
                destinationMetrics = targetMetrics(for: request)
            } else {
                destinationMetrics = chromeMetrics?.anchored(at: request.geometry.targetSize)
            }
            if let destinationMetrics {
                withAnimation(request.spring?.animation ?? NotchMotion.content) {
                    chromeMetrics = destinationMetrics
                }
            }

            guard request.targetState.isVisible else { return }
            let remainingFade = max(0, NotchMotion.removalDuration - request.shellDelay)
            if remainingFade > 0 {
                try? await Task.sleep(for: .seconds(remainingFade))
            }
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }
            withoutAnimation {
                activeTransition = .opacity
                displayedState = viewModel.surfaceState
                contentOpacity = 0
            }
            if request.contentDelay > 0 {
                try? await Task.sleep(for: .seconds(request.contentDelay))
            }
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }
            withAnimation(NotchMotion.insertion) {
                contentOpacity = 1
                contentOffsetY = 0
            }
        }
    }

    private func beginReducedMotionTransition(_ request: PanelMorphRequest) {
        if !request.targetState.isVisible {
            return
        }
        guard let targetMetrics = targetMetrics(for: request) else { return }
        if !request.wasVisible {
            withoutAnimation {
                displayedState = viewModel.surfaceState
                chromeMetrics = targetMetrics
                surfaceOpacity = 1
                contentOpacity = 1
                contentOffsetY = 0
            }
            return
        }

        let halfDuration = NotchMotion.reducedMotionDuration / 2
        morphTask = Task { @MainActor in
            withAnimation(NotchMotion.easeOut(duration: halfDuration)) {
                surfaceOpacity = 0
            }
            try? await Task.sleep(for: .seconds(halfDuration))
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }
            withoutAnimation {
                activeTransition = .opacity
                displayedState = viewModel.surfaceState
                chromeMetrics = targetMetrics
                surfaceOpacity = 0
                contentOpacity = 1
                contentOffsetY = 0
            }
            withAnimation(NotchMotion.easeOut(duration: halfDuration)) {
                surfaceOpacity = 1
            }
        }
    }

    private func targetMetrics(for request: PanelMorphRequest) -> SurfaceChromeMetrics? {
        SurfaceChromeMetrics.resolve(for: viewModel.surfaceState)?
            .replacing(size: request.geometry.targetSize)
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
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
        .environmentObject(PanelMorphCoordinator())
        .padding(40)
        .background(Color.gray.opacity(0.35))
}

#Preview("Collapsed") {
    let model = AppViewModel.preview
    model.surfaceState = .collapsed
    return NotchSurfaceView(viewModel: model)
        .environmentObject(PanelMorphCoordinator())
        .padding(40)
}
#endif
