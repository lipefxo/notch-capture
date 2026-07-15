import AppKit
import QuartzCore
import SwiftUI

struct PanelTransitionPolicy: Equatable {
    enum Kind: Equatable {
        case immediate
        case expand
        case contract
    }

    let kind: Kind
    let duration: TimeInterval

    var animatesFrame: Bool {
        kind != .immediate && duration > 0
    }

    static func resolve(
        from oldState: PanelState,
        to newState: PanelState,
        wasVisible: Bool,
        reduceMotion: Bool
    ) -> Self {
        guard newState.isVisible, !reduceMotion else {
            return Self(kind: .immediate, duration: 0)
        }
        guard oldState != newState || !wasVisible else {
            return Self(kind: .immediate, duration: 0)
        }

        if !wasVisible {
            return newState == .collapsed
                ? Self(kind: .immediate, duration: 0)
                : Self(kind: .expand, duration: NotchMotion.surfaceExpansionDuration)
        }

        let oldArea = oldState.nominalSize.width * oldState.nominalSize.height
        let newArea = newState.nominalSize.width * newState.nominalSize.height
        if newArea > oldArea {
            return Self(kind: .expand, duration: NotchMotion.surfaceExpansionDuration)
        }
        if newArea < oldArea {
            return Self(kind: .contract, duration: NotchMotion.surfaceContractionDuration)
        }
        return Self(kind: .immediate, duration: 0)
    }
}

@MainActor
public final class PanelController: NSObject, ObservableObject {
    public typealias ContentFactory = @MainActor (PanelState) -> AnyView

    @Published public private(set) var state: PanelState = .dormant
    public var onRequestDismiss: (@MainActor () -> Void)?

    public let panel: NotchPanel

    private let displayLocator: any DisplayLocating
    private let contentFactory: ContentFactory
    private let automaticDismissalEnabled: Bool
    private let hostingView: NSHostingView<AnyView>
    private var targetScreen: NSScreen?
    private weak var previouslyActiveApplication: NSRunningApplication?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var confirmationDismissalTask: Task<Void, Never>?
    private var transitionGeneration = 0

    public init(
        displayLocator: any DisplayLocating = DisplayLocator(),
        automaticDismissalEnabled: Bool = true,
        content: @escaping ContentFactory
    ) {
        self.displayLocator = displayLocator
        self.automaticDismissalEnabled = automaticDismissalEnabled
        self.contentFactory = content
        self.hostingView = NSHostingView(rootView: content(.dormant))
        self.panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        panel.contentView = hostingView
    }

    deinit {
        confirmationDismissalTask?.cancel()
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
        let wasVisible = panel.isVisible && oldState.isVisible
        guard oldState != newState || !wasVisible else { return }
        confirmationDismissalTask?.cancel()

        targetScreen = screen ?? displayLocator.pointerScreen
        guard let targetFrame = panelFrame(for: newState) else { return }
        let transition = PanelTransitionPolicy.resolve(
            from: oldState,
            to: newState,
            wasVisible: wasVisible,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        state = newState
        panel.permitsKeyWindow = newState.acceptsKeyboardInput
        panel.level = newState.isExplicitSession
            ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
            : .statusBar
        installDismissalMonitorsIfNeeded()

        transitionGeneration += 1
        let generation = transitionGeneration
        let contractsToPill = transition.kind == .contract && newState == .collapsed
        panel.ignoresMouseEvents = contractsToPill

        if !wasVisible {
            let sourceFrame = transition.animatesFrame
                ? panelFrame(for: .collapsed) ?? targetFrame
                : targetFrame
            panel.setFrame(sourceFrame, display: false)
        }

        if activate && newState.acceptsKeyboardInput {
            rememberPreviousApplication()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        animatePanel(
            to: targetFrame,
            transition: transition,
            generation: generation,
            restoreHitTesting: contractsToPill
        )

        if newState == .confirmation {
            scheduleConfirmationDismissal()
        }
    }

    /// Recalculates the panel position after a screen arrangement or resolution change.
    public func reposition(on screen: NSScreen? = nil) {
        targetScreen = screen ?? targetScreen ?? displayLocator.pointerScreen
        guard state.isVisible else { return }
        guard let frame = panelFrame(for: state) else { return }
        transitionGeneration += 1
        panel.setFrame(frame, display: true)
    }

#if DEBUG
    /// Captures the live hosted panel without requiring Screen Recording permission.
    public func writeSnapshot(to destination: URL) throws {
        guard state.isVisible, let contentView = panel.contentView else {
            throw PanelSnapshotError.surfaceUnavailable
        }
        panel.displayIfNeeded()
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        contentView.needsDisplay = true
        contentView.display()
        let bounds = contentView.bounds
        guard !bounds.isEmpty,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw PanelSnapshotError.surfaceUnavailable
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
    public func dismiss(restoringFocus: Bool = true) {
        transitionToHiddenState(.dormant)
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
        panel.hasShadow = true
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

    private func transitionToHiddenState(_ hiddenState: PanelState) {
        confirmationDismissalTask?.cancel()
        confirmationDismissalTask = nil
        transitionGeneration += 1
        state = hiddenState
        panel.ignoresMouseEvents = false
        panel.orderOut(nil)
        removeDismissalMonitors()
    }

    private func panelFrame(for state: PanelState) -> CGRect? {
        guard
            let screen = targetScreen ?? displayLocator.pointerScreen,
            let geometry = displayLocator.geometry(for: screen)
        else {
            assertionFailure("A visible notch surface requires an available display geometry.")
            return nil
        }

        var size = state.nominalSize
        if state == .collapsed {
            let notchWidth = geometry.notchRect?.width ?? 156
            size.width = max(size.width, notchWidth + 24)
            size.height = max(size.height, geometry.safeAreaInsets.top + 6)
        } else if [.expanded, .dropTarget, .onboarding, .settings].contains(state) {
            size.height = min(size.height, geometry.screenFrame.height - 28)
        }

        guard size.width > 0, size.height > 0 else { return nil }
        return geometry.panelFrame(for: size)
    }

    private func animatePanel(
        to targetFrame: CGRect,
        transition: PanelTransitionPolicy,
        generation: Int,
        restoreHitTesting: Bool
    ) {
        guard transition.animatesFrame, panel.frame != targetFrame else {
            panel.setFrame(targetFrame, display: true)
            if restoreHitTesting { panel.ignoresMouseEvents = false }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transition.duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                if restoreHitTesting { self.panel.ignoresMouseEvents = false }
            }
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
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.requestDismissal()
                    return nil
                }
                if event.window !== self.panel, event.type != .keyDown {
                    self.requestDismissal()
                }
                return event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.requestDismissal()
            }
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
            self?.requestDismissal()
        }
    }

    private func requestDismissal() {
        if let onRequestDismiss {
            onRequestDismiss()
        } else {
            dismiss()
        }
    }
}

#if DEBUG
private enum PanelSnapshotError: LocalizedError {
    case surfaceUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .surfaceUnavailable: "The rendered notch surface is unavailable."
        case .encodingFailed: "The rendered notch surface could not be encoded."
        }
    }
}
#endif
