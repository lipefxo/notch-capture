import SwiftUI

struct SurfaceChromeMetrics: Equatable {
    let size: CGSize
    let bottomRadius: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    /// Sizes come from `PanelState.nominalSize` — the AppKit window and the
    /// SwiftUI chrome must never disagree about surface dimensions.
    static func resolve(
        for state: AppViewModel.SurfaceState,
        compactPresentationSize: CompactPresentationSize = .minimal,
        activityLayout: AppViewModel.CollapsedActivityLayout? = nil
    ) -> Self? {
        switch state {
        case .dormant:
            return nil
        case .collapsed, .collapsedActivity:
            let compactMetrics = CompactSurfaceMetrics.resolve(
                state: state.panelState,
                presentationSize: compactPresentationSize,
                activityLayout: activityLayout
            )!
            return Self(
                size: compactMetrics.shellSize,
                bottomRadius: compactMetrics.bottomRadius,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0
            )
        case .volume, .confirmation, .notification, .expanded, .drop, .onboarding, .settings, .mirror:
            return Self(
                size: state.panelState.nominalSize,
                bottomRadius: NotchTheme.surfaceBottomRadius,
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
    @EnvironmentObject private var presentation: NotchPresentationCoordinator
    @State private var displayedState: AppViewModel.SurfaceState?
    @State private var displayedCompactPresentationSize: CompactPresentationSize
    @State private var chromeMetrics: SurfaceChromeMetrics?
    @State private var activeTransition: AnyTransition = .opacity
    @State private var surfaceOpacity = 1.0
    @State private var contentOpacity = 1.0
    @State private var contentOffsetY: CGFloat = 0
    @State private var contentScale = 1.0
    @State private var morphTask: Task<Void, Never>?
    // The hosting view's very first commit reliably fails to paint the final
    // glyph run of the scene (the collapsed pill's trailing shortcut hint
    // renders blank) even though layout is correct; only recreating the content
    // subtree repaints it. Bumped once shortly after launch, the id change
    // rebuilds the content with fresh layers. See PanelController's present
    // pipeline for the launch ordering.
    @State private var initialCommitRepaint = 0

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _displayedCompactPresentationSize = State(
            initialValue: viewModel.effectiveCompactPresentationSize
        )
        _displayedState = State(
            initialValue: chromeMetrics(for: viewModel) == nil
                ? nil
                : viewModel.surfaceState
        )
        _chromeMetrics = State(initialValue: Self.chromeMetrics(for: viewModel))
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

                    if displayedState == .collapsedActivity,
                       viewModel.collapsedActivityLayout.hasHardwareNotch {
                        Button {
                            guard viewModel.surfaceState == .collapsedActivity else { return }
                            viewModel.openExpanded()
                        } label: {
                            Color.clear
                                .contentShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                        }
                        .buttonStyle(.plain)
                        .frame(width: metrics.size.width, height: metrics.size.height)
                        .disabled(presentation.hasModal)
                        .help("Open Notch Capture")
                        .accessibilityLabel("Open Notch Capture")
                    }

                    ZStack {
                        surfaceContent(for: displayedState)
                            .id("\(contentIdentity(for: displayedState))#\(initialCommitRepaint)")
                            .transition(activeTransition)
                            .disabled(presentation.hasModal)
                            .accessibilityHidden(presentation.hasModal)

                        NotchPresentationLayer(viewModel: viewModel)
                    }
                    .coordinateSpace(name: NotchPresentationLayer.coordinateSpace)
                    .environmentObject(presentation)
                    // Content lays out in the visible body; the surface frame is
                    // wider by one top-flare wing per side.
                    .padding(.horizontal, NotchTheme.topFlare)
                    .clipShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                    .opacity(contentOpacity)
                    .offset(y: contentOffsetY)
                    .scaleEffect(contentScale, anchor: .top)
                }
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
                .contentShape(NotchHugShape(bottomRadius: metrics.bottomRadius))
                .opacity(surfaceOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .symbolVariant(.fill)
        .onChange(of: viewModel.surfaceState) { oldState, newState in
            handleSurfaceStateChange(from: oldState, to: newState)
        }
        .onChange(of: viewModel.collapsedActivityLayout) { _, _ in
            refreshCompactChrome()
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
        case .dormant:
            EmptyView()
        case .collapsed:
            CollapsedPillView(
                viewModel: viewModel,
                presentationSize: displayedCompactPresentationSize
            )
        case .collapsedActivity:
            CollapsedActivityPillView(
                viewModel: viewModel,
                presentationSize: displayedCompactPresentationSize
            )
        case .volume:
            VolumeControlSurfaceView(viewModel: viewModel)
        case .confirmation:
            ConfirmationView(viewModel: viewModel)
        case .notification:
            NotchNotificationView(viewModel: viewModel)
        case .expanded, .drop:
            ExpandedInboxView(viewModel: viewModel)
        case .onboarding:
            OnboardingView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        case .mirror:
            MirrorSurfaceView(viewModel: viewModel)
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
        // Presentation teardown on state changes is owned by AppCoordinator's
        // state sink, which runs even when this view's updates are deferred.

        guard let newMetrics = chromeMetrics(for: viewModel, state: newState) else {
            // The morph coordinator keeps the last visible shell mounted while
            // AppKit completes the retreat into the notch.
            return
        }
        if isDropOnlyTransition(from: oldState, to: newState) {
            morphTask?.cancel()
            displayedState = newState
            displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
            chromeMetrics = newMetrics
            surfaceOpacity = 1
            contentOpacity = 1
            contentOffsetY = 0
            contentScale = 1
            return
        }

        guard let oldMetrics = chromeMetrics(for: viewModel, state: oldState),
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
            displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
            chromeMetrics = newMetrics
            surfaceOpacity = 1
            contentOpacity = 1
            contentOffsetY = 0
            contentScale = 1
        }
    }

    private func handleMorphRequest(_ request: PanelMorphRequest) {
        switch request.phase {
        case .prepared:
            prepareMorph(request)
        case .active:
            beginMorph(request)
        case .settled:
            // Repainting mid-morph re-drops the glyphs, so the rebuild waits
            // for the first settled transition. Scope the repair to non-key
            // surfaces that can remain visible unattended; recreating a
            // keyboard surface here would risk resetting its focus.
            if viewModel.surfaceState == .volume {
                // The focused row is a newly mounted compact subtree each
                // time it opens, so give each settled presentation one repair.
                withoutAnimation { initialCommitRepaint += 1 }
            } else if initialCommitRepaint == 0,
                      [.collapsed, .collapsedActivity, .confirmation, .notification, .mirror]
                          .contains(viewModel.surfaceState) {
                withoutAnimation { initialCommitRepaint = 1 }
            }
        }
    }

    private func prepareMorph(_ request: PanelMorphRequest) {
        morphTask?.cancel()
        guard request.targetState.isVisible,
              let targetMetrics = targetMetrics(for: request) else { return }
        withoutAnimation {
            activeTransition = .opacity
            displayedState = viewModel.surfaceState
            displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
            chromeMetrics = targetMetrics.anchored(at: request.geometry.sourceSize)
            surfaceOpacity = 1
            contentOpacity = 0
            contentOffsetY = -NotchMotion.surfaceContentOffset
            contentScale = 0.97
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

        let hasVisibleSource = request.wasVisible && displayedState != nil
        withoutAnimation {
            activeTransition = liquidContentTransition
            if chromeMetrics == nil {
                chromeMetrics = targetMetrics.anchored(at: request.geometry.sourceSize)
            }
            surfaceOpacity = 1
            if !hasVisibleSource {
                displayedState = viewModel.surfaceState
                contentOpacity = 0
                contentOffsetY = -NotchMotion.surfaceContentOffset
                contentScale = 0.97
            }
        }
        withAnimation(request.spring?.animation ?? NotchMotion.content) {
            chromeMetrics = targetMetrics
        }

        if hasVisibleSource {
            withAnimation(NotchMotion.surfaceContentReveal) {
                displayedState = viewModel.surfaceState
                displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
                contentOpacity = 1
                contentOffsetY = 0
                contentScale = 1
            }
            return
        }

        morphTask = Task { @MainActor in
            if request.contentDelay > 0 {
                try? await Task.sleep(for: .seconds(request.contentDelay))
            }
            guard !Task.isCancelled, morphCoordinator.request?.generation == request.generation else { return }
            withAnimation(NotchMotion.surfaceContentReveal) {
                contentOpacity = 1
                contentOffsetY = 0
                contentScale = 1
            }
        }
    }

    private func beginContraction(_ request: PanelMorphRequest) {
        surfaceOpacity = 1
        activeTransition = liquidContentTransition

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

        if request.targetState.isVisible {
            withAnimation(NotchMotion.surfaceContentReveal) {
                displayedState = viewModel.surfaceState
                displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
                contentOpacity = 1
                contentOffsetY = 0
                contentScale = 1
            }
        } else {
            withAnimation(NotchMotion.easeOut(duration: 0.20)) {
                contentOpacity = 0
                contentOffsetY = -NotchMotion.surfaceContentOffset
                contentScale = 0.97
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
                displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
                chromeMetrics = targetMetrics
                surfaceOpacity = 1
                contentOpacity = 1
                contentOffsetY = 0
                contentScale = 1
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
                displayedCompactPresentationSize = viewModel.effectiveCompactPresentationSize
                chromeMetrics = targetMetrics
                surfaceOpacity = 0
                contentOpacity = 1
                contentOffsetY = 0
                contentScale = 1
            }
            withAnimation(NotchMotion.easeOut(duration: halfDuration)) {
                surfaceOpacity = 1
            }
        }
    }

    private func targetMetrics(for request: PanelMorphRequest) -> SurfaceChromeMetrics? {
        chromeMetrics(for: viewModel)?
            .replacing(size: request.geometry.targetSize)
    }

    private static func chromeMetrics(
        for viewModel: AppViewModel,
        state: AppViewModel.SurfaceState? = nil
    ) -> SurfaceChromeMetrics? {
        SurfaceChromeMetrics.resolve(
            for: state ?? viewModel.surfaceState,
            compactPresentationSize: viewModel.effectiveCompactPresentationSize,
            activityLayout: viewModel.collapsedActivityLayout
        )
    }

    private func chromeMetrics(
        for viewModel: AppViewModel,
        state: AppViewModel.SurfaceState? = nil
    ) -> SurfaceChromeMetrics? {
        Self.chromeMetrics(for: viewModel, state: state)
    }

    private func refreshCompactChrome() {
        guard [.collapsed, .collapsedActivity].contains(viewModel.surfaceState),
              let metrics = chromeMetrics(for: viewModel) else { return }
        withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content) {
            chromeMetrics = metrics
        }
    }

    private var liquidContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
        )
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
        case .collapsed: "collapsed-\(displayedCompactPresentationSize.rawValue)"
        case .collapsedActivity: "collapsedActivity-\(displayedCompactPresentationSize.rawValue)"
        case .volume: "volume"
        case .confirmation: "confirmation"
        case .notification: "notification"
        case .onboarding: "onboarding"
        case .settings: "settings"
        case .mirror: "mirror"
        }
    }

    private func transition(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        let pillStates: Set<AppViewModel.SurfaceState> = [.collapsed, .collapsedActivity]
        if pillStates.contains(oldState), pillStates.contains(newState) {
            return .opacity
        }

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
    let presentationSize: CompactPresentationSize
    @State private var isHovered = false

    private var metrics: CompactSurfaceMetrics {
        CompactSurfaceMetrics.capture(for: presentationSize)
    }

    private var isExtended: Bool { presentationSize == .extended }

    /// The audio affordance owns a fixed trailing slot, keeping the capture
    /// cluster at its established width.
    private var captureWidth: CGFloat {
        metrics.contentSize.width - CompactSurfaceMetrics.audioControlSlot
    }

    var body: some View {
        HStack(spacing: 0) {
            captureButton
            CompactVolumeButton(
                viewModel: viewModel,
                glyphSize: isExtended ? 12 : 10.5
            )
        }
        .frame(width: metrics.contentSize.width, height: metrics.contentSize.height)
    }

    private var captureButton: some View {
        Button {
            viewModel.openExpanded()
        } label: {
            HStack(spacing: isExtended ? 12 : 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: isExtended ? 16 : 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryAccent)
                Text("Capture")
                    .font(.system(size: isExtended ? 14 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(viewModel.shortcutDisplayValue(for: .openComposer))
                    .font(.system(size: isExtended ? 11 : 9, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .frame(width: captureWidth, height: metrics.contentSize.height)
            .overlay(alignment: .bottom) {
                if !isExtended {
                    Capsule()
                        .fill(isHovered ? NotchTheme.primaryAccent.opacity(0.65) : Color.white.opacity(0.1))
                        .frame(width: 38, height: 1)
                        .scaleEffect(x: isHovered ? 1 : 22 / 38)
                        .padding(.bottom, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
        .notchHitTarget(Rectangle())
        .onHover { isHovered = $0 }
        .animation(NotchMotion.hover, value: isHovered)
        .help("Open Notch Capture")
        .accessibilityLabel("Open Notch Capture")
        .accessibilityHint("Opens the capture composer and inbox")
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
