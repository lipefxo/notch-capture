import AppKit
import QuartzCore
import SwiftUI

struct PanelTransitionPolicy: Equatable {
    enum Kind: Equatable {
        case immediate
        case expand
        case contract
        case hide
        case reducedFade
    }

    enum Opacity: Equatable {
        case unchanged
        case reveal
        case hide
    }

    let kind: Kind
    let spring: NotchSpringProfile?
    let opacity: Opacity
    let fadeDuration: TimeInterval

    var duration: TimeInterval {
        max(spring?.perceptualDuration ?? 0, fadeDuration)
    }

    var animatesMorph: Bool {
        spring != nil
    }

    var animatesOpacity: Bool {
        opacity != .unchanged && fadeDuration > 0
    }

    var ordersOutOnCompletion: Bool {
        opacity == .hide
    }

    static func resolve(
        from oldState: PanelState,
        to newState: PanelState,
        wasVisible: Bool,
        reduceMotion: Bool,
        animated: Bool = true
    ) -> Self {
        guard animated else { return .immediate }
        guard oldState != newState || !wasVisible else { return .immediate }

        if !newState.isVisible {
            guard newState != .screenshot, wasVisible else { return .immediate }
            if reduceMotion {
                return Self(
                    kind: .reducedFade,
                    spring: nil,
                    opacity: .hide,
                    fadeDuration: NotchMotion.reducedMotionDuration
                )
            }
            return Self(
                kind: .hide,
                spring: NotchMotion.surfaceHide,
                opacity: .hide,
                fadeDuration: NotchMotion.removalDuration
            )
        }

        if reduceMotion {
            return Self(
                kind: .reducedFade,
                spring: nil,
                opacity: wasVisible ? .unchanged : .reveal,
                fadeDuration: NotchMotion.reducedMotionDuration
            )
        }

        if !wasVisible {
            return Self(
                kind: .expand,
                spring: NotchMotion.surfaceExpansion,
                opacity: .unchanged,
                fadeDuration: 0
            )
        }

        let recoveringFromHide = !oldState.isVisible && wasVisible
        let oldArea = oldState.nominalSize.width * oldState.nominalSize.height
        let newArea = newState.nominalSize.width * newState.nominalSize.height
        if newArea > oldArea {
            return Self(
                kind: .expand,
                spring: NotchMotion.surfaceExpansion,
                opacity: recoveringFromHide ? .reveal : .unchanged,
                fadeDuration: recoveringFromHide ? NotchMotion.insertionDuration : 0
            )
        }
        if newArea < oldArea {
            return Self(
                kind: .contract,
                spring: NotchMotion.surfaceContraction,
                opacity: .unchanged,
                fadeDuration: 0
            )
        }
        return .immediate
    }

    private static let immediate = Self(
        kind: .immediate,
        spring: nil,
        opacity: .unchanged,
        fadeDuration: 0
    )
}

struct PanelDismissalEventPolicy {
    /// Mouse events delivered to this process belong to the notch panel or to
    /// one of its auxiliary dialogs. Clicks in other applications are handled
    /// by the global event monitor below.
    static let localEventMask: NSEvent.EventTypeMask = [.keyDown]

    static func shouldDismissForEscape(
        eventWindow: NSWindow?,
        panel: NSWindow
    ) -> Bool {
        eventWindow === panel
    }

    static func shouldDismissForExternalClick(hasVisibleAuxiliaryWindow: Bool) -> Bool {
        !hasVisibleAuxiliaryWindow
    }
}

struct PanelWindowInteractionPolicy {
    static func suspendsHitTesting(
        during transition: PanelTransitionPolicy,
        targetState: PanelState,
        wasVisible: Bool
    ) -> Bool {
        guard wasVisible, targetState == .collapsed else { return false }
        return transition.kind == .contract || transition.kind == .reducedFade
    }

    static func canRestoreHitTesting(
        actualFrame: CGRect,
        targetFrame: CGRect
    ) -> Bool {
        actualFrame == targetFrame
    }
}

/// Transparent margin reserved around a rendered surface inside the panel
/// window. Open surfaces need room for their drop shadow, while the collapsed
/// pill deliberately has no outer shadow so its window can match its hit area.
struct PanelShadowApron: Equatable {
    let horizontal: CGFloat
    let bottom: CGFloat

    static let none = Self(horizontal: 0, bottom: 0)
    static let standard = Self(horizontal: 64, bottom: 80)

    static func resolve(for state: PanelState) -> Self {
        state == .collapsed ? .none : .standard
    }

    func applying(to size: CGSize) -> CGSize {
        CGSize(
            width: size.width + horizontal * 2,
            height: size.height + bottom
        )
    }
}

public enum PanelDismissalReason: Equatable {
    case escape
    case externalClick
    case automatic
}

@MainActor
public final class PanelController: NSObject, ObservableObject {
    public typealias ContentFactory = @MainActor (PanelState) -> AnyView

    @Published public private(set) var state: PanelState = .dormant
    public var onRequestDismiss: (@MainActor (PanelDismissalReason) -> Void)?

    public let panel: NotchPanel

    private let displayLocator: any DisplayLocating
    private let automaticDismissalEnabled: Bool
    private let hostingView: NSHostingView<AnyView>
    private let morphCoordinator: PanelMorphCoordinator
    private var targetScreen: NSScreen?
    private weak var previouslyActiveApplication: NSRunningApplication?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var confirmationDismissalTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = 0

    public init(
        displayLocator: any DisplayLocating = DisplayLocator(),
        automaticDismissalEnabled: Bool = true,
        content: @escaping ContentFactory
    ) {
        let morphCoordinator = PanelMorphCoordinator()
        self.displayLocator = displayLocator
        self.automaticDismissalEnabled = automaticDismissalEnabled
        self.morphCoordinator = morphCoordinator
        self.hostingView = NSHostingView(
            rootView: AnyView(content(.dormant).environmentObject(morphCoordinator))
        )
        self.panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
        // PanelController owns the window geometry. The NSHostingView default
        // sizing options otherwise feed SwiftUI's current minimum size back
        // into NSWindow and can clamp a closing panel to its expanded frame.
        hostingView.sizingOptions = []
        configurePanel()
        panel.contentView = hostingView
        panel.contentMinSize = .zero
    }

    deinit {
        confirmationDismissalTask?.cancel()
        transitionTask?.cancel()
        MainActor.assumeIsolated {
            if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
            if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        }
    }

    /// Presents a state on the supplied screen, or on the screen under the pointer.
    /// Set `activate` for states that require typing. Passive confirmation never
    /// steals focus from the source application.
    public func present(
        _ newState: PanelState,
        on screen: NSScreen? = nil,
        activate: Bool = false
    ) {
        guard newState.isVisible else {
            transitionToHiddenState(newState)
            return
        }

        let oldState = state
        let wasVisible = panel.isVisible
        guard oldState != newState || !wasVisible else { return }
        confirmationDismissalTask?.cancel()

        targetScreen = screen ?? displayLocator.pointerScreen
        guard let geometry = targetGeometry,
              let targetFrame = panelFrame(for: newState, geometry: geometry) else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transition = PanelTransitionPolicy.resolve(
            from: oldState,
            to: newState,
            wasVisible: wasVisible,
            reduceMotion: reduceMotion
        )

        state = newState
        panel.permitsKeyWindow = newState.acceptsKeyboardInput
        panel.level = newState.isExplicitSession
            ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
            : .statusBar
        installDismissalMonitorsIfNeeded()

        transitionGeneration += 1
        let generation = transitionGeneration
        let contractsToPill = PanelWindowInteractionPolicy.suspendsHitTesting(
            during: transition,
            targetState: newState,
            wasVisible: wasVisible
        )
        panel.ignoresMouseEvents = contractsToPill

        let morphGeometry = PanelMorphGeometry(
            topCenter: CGPoint(x: targetFrame.midX, y: geometry.screenFrame.maxY),
            sourceSize: morphSourceSize(
                for: oldState,
                targetState: newState,
                wasVisible: wasVisible,
                geometry: geometry
            ),
            targetSize: surfaceSize(for: newState, geometry: geometry)
        )
        let request = morphRequest(
            generation: generation,
            geometry: morphGeometry,
            targetState: newState,
            transition: transition,
            reduceMotion: reduceMotion,
            wasVisible: wasVisible
        )
        let usesMorphCoordinator = transition.animatesMorph || transition.kind == .reducedFade

        if usesMorphCoordinator && (!reduceMotion || wasVisible) {
            panel.setFrame(
                transitionCanvasFrame(
                    for: morphGeometry,
                    targetFrame: targetFrame,
                    targetState: newState,
                    includeCurrentFrame: wasVisible
                ),
                display: false
            )
        } else {
            panel.setFrame(targetFrame, display: false)
        }
        if !wasVisible {
            panel.alphaValue = transition.opacity == .reveal ? 0 : 1
        }

        if usesMorphCoordinator {
            if !wasVisible && !reduceMotion {
                morphCoordinator.prepare(request)
            } else {
                morphCoordinator.begin(request)
            }
        }

        if activate && newState.acceptsKeyboardInput {
            rememberPreviousApplication()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        if usesMorphCoordinator {
            runPanelTransition(
                request: request,
                transition: transition,
                targetFrame: targetFrame,
                restoreHitTesting: contractsToPill,
                deferActivation: !wasVisible && !reduceMotion
            )
        } else {
            transitionTask?.cancel()
            morphCoordinator.cancel()
            panel.alphaValue = 1
            if contractsToPill { panel.ignoresMouseEvents = false }
        }

        if newState == .confirmation {
            scheduleConfirmationDismissal()
        }
    }

    /// Recalculates the panel position after a screen arrangement or resolution change.
    public func reposition(on screen: NSScreen? = nil) {
        targetScreen = screen ?? targetScreen ?? displayLocator.pointerScreen
        guard state.isVisible else { return }
        guard let frame = panelFrame(for: state) else { return }
        transitionTask?.cancel()
        if let generation = morphCoordinator.request?.generation {
            morphCoordinator.settle(generation: generation)
        }
        transitionGeneration += 1
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }

#if DEBUG
    /// Captures the live hosted panel without requiring Screen Recording permission.
    public func writeSnapshot(to destination: URL) throws {
        guard state.isVisible else { throw PanelSnapshotError.panelHidden(state) }
        guard let contentView = panel.contentView else { throw PanelSnapshotError.missingContentView }
        panel.displayIfNeeded()
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        contentView.needsDisplay = true
        contentView.display()
        let bounds = contentView.bounds
        guard !bounds.isEmpty,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw PanelSnapshotError.emptySurface(bounds)
        }
        contentView.cacheDisplay(in: bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw PanelSnapshotError.encodingFailed
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: destination, options: .atomic)
    }
#endif

    /// Removes every window and hit target owned by this controller.
    public func dismiss(restoringFocus: Bool = true, animated: Bool = true) {
        transitionToHiddenState(.dormant, animated: animated)
        if restoringFocus {
            restorePreviousApplication()
        } else {
            previouslyActiveApplication = nil
        }
    }

    public func restoreFocus() {
        restorePreviousApplication()
    }

    public func setConfirmationDismissalPaused(_ paused: Bool, remaining: TimeInterval) {
        guard state == .confirmation else { return }
        confirmationDismissalTask?.cancel()
        confirmationDismissalTask = nil
        if !paused {
            scheduleConfirmationDismissal(after: remaining)
        }
    }

    public func restartConfirmationDismissal() {
        guard state == .confirmation else { return }
        confirmationDismissalTask?.cancel()
        confirmationDismissalTask = nil
        scheduleConfirmationDismissal()
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.sharingType = .readOnly
        // The persistent SwiftUI shell owns its shape-aware shadow. AppKit's
        // window shadow follows the rectangular panel bounds and leaks a square
        // frame around the rounded Dynamic Island chrome.
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    private func transitionToHiddenState(_ hiddenState: PanelState, animated: Bool = true) {
        guard state != hiddenState else { return }
        confirmationDismissalTask?.cancel()
        confirmationDismissalTask = nil
        let oldState = state
        let wasVisible = panel.isVisible
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transition = PanelTransitionPolicy.resolve(
            from: oldState,
            to: hiddenState,
            wasVisible: wasVisible,
            reduceMotion: reduceMotion,
            animated: animated
        )

        transitionGeneration += 1
        let generation = transitionGeneration
        state = hiddenState
        panel.permitsKeyWindow = false
        panel.ignoresMouseEvents = true
        removeDismissalMonitors()

        guard wasVisible, transition.kind != .immediate, let geometry = targetGeometry else {
            transitionTask?.cancel()
            morphCoordinator.cancel()
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            return
        }

        let targetSize = PanelMorphGeometry.notchAnchorSize(for: geometry)
        let morphGeometry = PanelMorphGeometry(
            topCenter: CGPoint(x: panel.frame.midX, y: geometry.screenFrame.maxY),
            sourceSize: morphSourceSize(
                for: oldState,
                targetState: hiddenState,
                wasVisible: true,
                geometry: geometry
            ),
            targetSize: targetSize
        )
        let request = morphRequest(
            generation: generation,
            geometry: morphGeometry,
            targetState: hiddenState,
            transition: transition,
            reduceMotion: reduceMotion,
            wasVisible: true
        )
        morphCoordinator.begin(request)
        runPanelTransition(
            request: request,
            transition: transition,
            targetFrame: panel.frame,
            restoreHitTesting: false,
            deferActivation: false
        )
    }

    private var targetGeometry: NotchGeometry? {
        guard let screen = targetScreen ?? displayLocator.pointerScreen else { return nil }
        return displayLocator.geometry(for: screen)
    }

    private func panelFrame(for state: PanelState) -> CGRect? {
        guard let geometry = targetGeometry else {
            assertionFailure("A visible notch surface requires an available display geometry.")
            return nil
        }
        return panelFrame(for: state, geometry: geometry)
    }

    private func panelFrame(for state: PanelState, geometry: NotchGeometry) -> CGRect? {
        var size = surfaceSize(for: state, geometry: geometry)
        if state == .collapsed {
            let notchWidth = geometry.notchRect?.width ?? PanelMorphGeometry.virtualNotchSize.width
            size.width = max(size.width, notchWidth + 24)
            size.height = max(size.height, geometry.safeAreaInsets.top + 6)
        }
        guard size.width > 0, size.height > 0 else { return nil }
        size = PanelShadowApron.resolve(for: state).applying(to: size)
        return geometry.panelFrame(for: size)
    }

    private func surfaceSize(for state: PanelState, geometry: NotchGeometry) -> CGSize {
        var size = state.nominalSize
        if [.expanded, .dropTarget, .onboarding, .settings].contains(state) {
            size.height = min(size.height, geometry.screenFrame.height - 28)
        }
        return size
    }

    private func morphSourceSize(
        for state: PanelState,
        targetState: PanelState,
        wasVisible: Bool,
        geometry: NotchGeometry
    ) -> CGSize {
        guard wasVisible else {
            return PanelMorphGeometry.concealedAnchorSize(
                for: geometry,
                targetSize: surfaceSize(for: targetState, geometry: geometry)
            )
        }
        if state.isVisible {
            return surfaceSize(for: state, geometry: geometry)
        }
        return morphCoordinator.request?.geometry.targetSize
            ?? PanelMorphGeometry.notchAnchorSize(for: geometry)
    }

    private func transitionCanvasFrame(
        for geometry: PanelMorphGeometry,
        targetFrame: CGRect,
        targetState: PanelState,
        includeCurrentFrame: Bool
    ) -> CGRect {
        let apron = PanelShadowApron.resolve(for: targetState)
        let requested = geometry.panelCanvasFrame(
            horizontalApron: apron.horizontal,
            bottomApron: apron.bottom
        )
        let width = max(
            requested.width,
            targetFrame.width,
            includeCurrentFrame ? panel.frame.width : 0
        )
        let height = max(
            requested.height,
            targetFrame.height,
            includeCurrentFrame ? panel.frame.height : 0
        )
        return CGRect(
            x: targetFrame.midX - (width / 2),
            y: targetFrame.maxY - height,
            width: width,
            height: height
        ).integral
    }

    private func morphRequest(
        generation: Int,
        geometry: PanelMorphGeometry,
        targetState: PanelState,
        transition: PanelTransitionPolicy,
        reduceMotion: Bool,
        wasVisible: Bool
    ) -> PanelMorphRequest {
        return PanelMorphRequest(
            generation: generation,
            phase: .active,
            geometry: geometry,
            targetState: targetState,
            kind: transition.kind,
            spring: transition.spring,
            fadeDuration: transition.fadeDuration,
            shellDelay: 0,
            contentDelay: reduceMotion ? 0 : NotchMotion.surfaceContentDelay,
            reduceMotion: reduceMotion,
            wasVisible: wasVisible
        )
    }

    private func runPanelTransition(
        request: PanelMorphRequest,
        transition: PanelTransitionPolicy,
        targetFrame: CGRect,
        restoreHitTesting: Bool,
        deferActivation: Bool
    ) {
        transitionTask?.cancel()
        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if deferActivation {
                await Task.yield()
                guard !Task.isCancelled, self.transitionGeneration == request.generation else { return }
                self.morphCoordinator.activate(generation: request.generation)
            }

            if transition.opacity == .reveal {
                self.animatePanelAlpha(to: 1, duration: transition.fadeDuration)
            }

            if transition.opacity == .hide {
                let fadeDelay = max(0, request.totalDuration - transition.fadeDuration)
                if fadeDelay > 0 {
                    try? await Task.sleep(for: .seconds(fadeDelay))
                }
                guard !Task.isCancelled, self.transitionGeneration == request.generation else { return }
                self.animatePanelAlpha(to: 0, duration: transition.fadeDuration)
                if transition.fadeDuration > 0 {
                    try? await Task.sleep(for: .seconds(transition.fadeDuration))
                }
            } else if request.totalDuration > 0 {
                try? await Task.sleep(for: .seconds(request.totalDuration))
            }

            guard !Task.isCancelled, self.transitionGeneration == request.generation else { return }
            self.morphCoordinator.settle(generation: request.generation)
            if transition.ordersOutOnCompletion {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.ignoresMouseEvents = false
            } else {
                self.panel.setFrame(targetFrame, display: true)
                self.panel.alphaValue = 1
                if restoreHitTesting {
                    self.panel.ignoresMouseEvents = !PanelWindowInteractionPolicy.canRestoreHitTesting(
                        actualFrame: self.panel.frame,
                        targetFrame: targetFrame
                    )
                }
            }
        }
    }

    private func animatePanelAlpha(to alpha: CGFloat, duration: TimeInterval) {
        guard duration > 0 else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = alpha
        }
    }

    private func rememberPreviousApplication() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != currentPID {
            previouslyActiveApplication = frontmost
        }
    }

    private func restorePreviousApplication() {
        guard let application = previouslyActiveApplication, !application.isTerminated else {
            previouslyActiveApplication = nil
            return
        }
        application.activate(options: [])
        previouslyActiveApplication = nil
    }

    private func installDismissalMonitorsIfNeeded() {
        guard automaticDismissalEnabled else {
            removeDismissalMonitors()
            return
        }
        guard state.isExplicitSession else {
            removeDismissalMonitors()
            return
        }

        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: PanelDismissalEventPolicy.localEventMask
            ) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53,
                   PanelDismissalEventPolicy.shouldDismissForEscape(
                       eventWindow: event.window,
                       panel: self.panel
                   ) {
                    self.requestDismissal(reason: .escape)
                    return nil
                }
                return event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self,
                      PanelDismissalEventPolicy.shouldDismissForExternalClick(
                          hasVisibleAuxiliaryWindow: self.hasVisibleAuxiliaryWindow
                      ) else { return }
                self.requestDismissal(reason: .externalClick)
            }
        }
    }

    private var hasVisibleAuxiliaryWindow: Bool {
        NSApp.windows.contains { window in
            window !== panel && window.isVisible && !window.isMiniaturized
        }
    }

    private func removeDismissalMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func scheduleConfirmationDismissal(after delay: TimeInterval = 5) {
        guard automaticDismissalEnabled else { return }
        confirmationDismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            self?.requestDismissal(reason: .automatic)
        }
    }

    private func requestDismissal(reason: PanelDismissalReason) {
        if let onRequestDismiss {
            onRequestDismiss(reason)
        } else {
            dismiss()
        }
    }
}

#if DEBUG
private enum PanelSnapshotError: LocalizedError {
    case panelHidden(PanelState)
    case missingContentView
    case emptySurface(CGRect)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case let .panelHidden(state): "The rendered notch surface is hidden (\(state.rawValue))."
        case .missingContentView: "The rendered notch surface has no content view."
        case let .emptySurface(bounds): "The rendered notch surface has invalid bounds: \(bounds)."
        case .encodingFailed: "The rendered notch surface could not be encoded."
        }
    }
}
#endif
