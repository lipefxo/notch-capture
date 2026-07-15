import AppKit
import SwiftUI

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
        confirmationDismissalTask?.cancel()

        guard newState.isVisible else {
            transitionToHiddenState(newState)
            return
        }

        targetScreen = screen ?? displayLocator.pointerScreen
        state = newState
        hostingView.rootView = contentFactory(newState)
        panel.permitsKeyWindow = newState.acceptsKeyboardInput
        panel.level = newState.isExplicitSession
            ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
            : .statusBar
        layoutPanel(for: newState)
        installDismissalMonitorsIfNeeded()

        if activate && newState.acceptsKeyboardInput {
            rememberPreviousApplication()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        if newState == .confirmation {
            scheduleConfirmationDismissal()
        }
    }

    /// Recalculates the panel position after a screen arrangement or resolution change.
    public func reposition(on screen: NSScreen? = nil) {
        targetScreen = screen ?? targetScreen ?? displayLocator.pointerScreen
        guard state.isVisible else { return }
        layoutPanel(for: state)
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

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.sharingType = .readOnly
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
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
        state = hiddenState
        hostingView.rootView = contentFactory(hiddenState)
        panel.orderOut(nil)
        removeDismissalMonitors()
    }

    private func layoutPanel(for state: PanelState) {
        guard
            let screen = targetScreen ?? displayLocator.pointerScreen,
            let geometry = displayLocator.geometry(for: screen)
        else {
            assertionFailure("A visible notch surface requires an available display geometry.")
            return
        }

        let size: CGSize
        switch state {
        case .collapsed:
            let notchWidth = geometry.notchRect?.width ?? 156
            let height = max(36, geometry.safeAreaInsets.top + 6)
            size = CGSize(width: max(176, notchWidth + 24), height: height)
        case .confirmation:
            size = CGSize(width: 300, height: 72)
        case .expanded, .dropTarget, .onboarding, .settings:
            size = CGSize(width: 420, height: min(560, geometry.screenFrame.height - 28))
        case .dormant, .screenshot:
            return
        }

        let frame = geometry.panelFrame(for: size)
        panel.setFrame(frame, display: true)
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

    private func scheduleConfirmationDismissal() {
        guard automaticDismissalEnabled else { return }
        confirmationDismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
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
