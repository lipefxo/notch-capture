import AppKit
import CoreGraphics

public struct NotchGeometry: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaInsets: NSEdgeInsets
    public let notchRect: CGRect?

    public init(
        displayID: CGDirectDisplayID,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        notchRect: CGRect?
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.notchRect = notchRect
    }

    public var hasHardwareNotch: Bool {
        notchRect != nil && safeAreaInsets.top > 0
    }

    public var topCenter: CGPoint {
        CGPoint(x: screenFrame.midX, y: screenFrame.maxY)
    }

    public static func == (lhs: NotchGeometry, rhs: NotchGeometry) -> Bool {
        lhs.displayID == rhs.displayID
            && lhs.screenFrame == rhs.screenFrame
            && lhs.visibleFrame == rhs.visibleFrame
            && lhs.safeAreaInsets.top == rhs.safeAreaInsets.top
            && lhs.safeAreaInsets.left == rhs.safeAreaInsets.left
            && lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom
            && lhs.safeAreaInsets.right == rhs.safeAreaInsets.right
            && lhs.notchRect == rhs.notchRect
    }

    /// A frame whose top edge hugs the display's top edge and whose horizontal
    /// center follows the physical notch (or display center on external screens).
    public func panelFrame(for size: CGSize) -> CGRect {
        let centerX = notchRect?.midX ?? screenFrame.midX
        let originX = min(
            max(centerX - size.width / 2, screenFrame.minX),
            screenFrame.maxX - size.width
        )
        return CGRect(
            x: originX,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        ).integral
    }
}

@MainActor
public protocol DisplayLocating: AnyObject {
    var screens: [NSScreen] { get }
    var pointerScreen: NSScreen? { get }
    func screen(withID displayID: CGDirectDisplayID) -> NSScreen?
    func displayID(for screen: NSScreen) -> CGDirectDisplayID?
    func geometry(for screen: NSScreen) -> NotchGeometry?
}

@MainActor
public final class DisplayLocator: DisplayLocating {
    public init() {}

    public var screens: [NSScreen] {
        NSScreen.screens
    }

    public var pointerScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    public func screen(withID displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(for: $0) == displayID }
    }

    public func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    public func geometry(for screen: NSScreen) -> NotchGeometry? {
        guard let displayID = displayID(for: screen) else { return nil }

        let safeInsets = screen.safeAreaInsets
        let notchRect = physicalNotchRect(on: screen, safeInsets: safeInsets)
        return NotchGeometry(
            displayID: displayID,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: safeInsets,
            notchRect: notchRect
        )
    }

    private func physicalNotchRect(on screen: NSScreen, safeInsets: NSEdgeInsets) -> CGRect? {
        guard safeInsets.top > 0 else { return nil }

        guard
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        else { return nil }
        let gapWidth = right.minX - left.maxX
        guard !left.isEmpty, !right.isEmpty, gapWidth > 0 else { return nil }

        return CGRect(
            x: left.maxX,
            y: screen.frame.maxY - safeInsets.top,
            width: gapWidth,
            height: safeInsets.top
        ).integral
    }
}
