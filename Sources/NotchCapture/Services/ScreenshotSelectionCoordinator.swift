import AppKit
import Foundation

@MainActor
struct ScreenshotSelection {
    /// Display on which the drag began.
    let screen: NSScreen
    /// AppKit screen-local rectangle with a bottom-left origin.
    let rect: CGRect
}

@MainActor
final class ScreenshotSelectionCoordinator {
    typealias Completion = (ScreenshotSelection?) -> Void

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var completion: Completion?
    private var previousApplication: NSRunningApplication?

    var isSelecting: Bool { !windows.isEmpty }

    func begin(completion: @escaping Completion) {
        cancel(notify: false)
        self.completion = completion
        previousApplication = NSWorkspace.shared.frontmostApplication

        for screen in NSScreen.screens {
            let window = ScreenshotSelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none
            window.contentView = ScreenshotSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                onComplete: { [weak self] rect in
                    guard let self else { return }
                    self.finish(with: ScreenshotSelection(screen: screen, rect: rect))
                },
                onCancel: { [weak self] in self?.finish(with: nil) }
            )
            windows.append(window)
            window.orderFrontRegardless()
        }

        windows.first?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.finish(with: nil)
            return nil
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with selection: ScreenshotSelection?) {
        guard isSelecting || completion != nil else { return }
        let callback = completion
        completion = nil
        tearDownWindows()
        callback?(selection)
        if selection == nil {
            previousApplication?.activate(options: [])
        }
        previousApplication = nil
    }

    private func cancel(notify: Bool) {
        guard isSelecting || completion != nil else { return }
        let callback = completion
        completion = nil
        tearDownWindows()
        if notify { callback?(nil) }
        previousApplication = nil
    }

    private func tearDownWindows() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }
}

private final class ScreenshotSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void
    private var dragStart: CGPoint?
    private var pointer: CGPoint?
    private var selectionRect: CGRect?

    init(frame frameRect: NSRect, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        _ = window?.makeFirstResponder(self)
        let point = clamped(convert(event.locationInWindow, from: nil))
        dragStart = point
        pointer = point
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        selectionRect = normalizedRect(from: dragStart, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        let rect = normalizedRect(from: dragStart, to: point).intersection(bounds)
        self.dragStart = nil
        guard rect.width >= 2, rect.height >= 2 else {
            selectionRect = nil
            NSSound.beep()
            needsDisplay = true
            return
        }
        onComplete(rect.integral)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        if let selectionRect, selectionRect.width > 0, selectionRect.height > 0,
           let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()

            let outline = NSBezierPath(roundedRect: selectionRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }

        if let pointer {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.minX, y: pointer.y))
            path.line(to: CGPoint(x: bounds.maxX, y: pointer.y))
            path.move(to: CGPoint(x: pointer.x, y: bounds.minY))
            path.line(to: CGPoint(x: pointer.x, y: bounds.maxY))
            path.lineWidth = 0.5
            NSColor.white.withAlphaComponent(0.65).setStroke()
            path.stroke()
        }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
