import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
protocol ScreenCaptureServicing: Sendable {
    var hasPermission: Bool { get }
    func requestPermission() -> Bool
    /// Captures an AppKit screen-local rectangle (bottom-left origin) on `screen`.
    func captureRegion(_ region: CGRect, on screen: NSScreen) async throws -> Data
}

@MainActor
final class ScreenCaptureService: ScreenCaptureServicing, @unchecked Sendable {
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureRegion(_ region: CGRect, on screen: NSScreen) async throws -> Data {
        guard hasPermission else { throw ScreenCaptureError.permissionRequired }
        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let intersection = region.intersection(screenBounds)
        guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else {
            throw ScreenCaptureError.emptyRegion
        }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw ScreenCaptureError.displayUnavailable
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        // AppKit's screen-local coordinates use a bottom-left origin;
        // ScreenCaptureKit uses a top-left origin.
        configuration.sourceRect = CGRect(
            x: intersection.minX,
            y: screenBounds.maxY - intersection.maxY,
            width: intersection.width,
            height: intersection.height
        )
        let scale = screen.backingScaleFactor
        configuration.width = max(1, Int(configuration.sourceRect.width * scale))
        configuration.height = max(1, Int(configuration.sourceRect.height * scale))
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.encodingFailed }
        return data as Data
    }
}

enum ScreenCaptureError: LocalizedError {
    case permissionRequired
    case displayUnavailable
    case emptyRegion
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionRequired: "Screen Recording permission is required."
        case .displayUnavailable: "The selected display is no longer available."
        case .emptyRegion: "Select a non-empty screen region."
        case .encodingFailed: "The screenshot could not be encoded as PNG."
        }
    }
}
