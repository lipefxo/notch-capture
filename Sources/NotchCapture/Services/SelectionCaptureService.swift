import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol SelectionCapturing {
    var isAccessibilityTrusted: Bool { get }
    func requestAccessibilityAccess()
    func captureSelection() async throws -> SelectionCaptureResult
}

@MainActor
final class SelectionCaptureService: SelectionCapturing {
    private let pasteboard: NSPasteboard
    private let workspace: NSWorkspace
    private let copyDelay: Duration

    init(
        pasteboard: NSPasteboard = .general,
        workspace: NSWorkspace = .shared,
        copyDelay: Duration = .milliseconds(100)
    ) {
        self.pasteboard = pasteboard
        self.workspace = workspace
        self.copyDelay = copyDelay
    }

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityAccess() {
        // The public constant's value is stable, while importing the global CF variable is
        // diagnosed as shared mutable state under Swift 6 strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func captureSelection() async throws -> SelectionCaptureResult {
        let source = currentSource()
        if let selectedText = directlySelectedText(), !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SelectionCaptureResult(payload: .text(selectedText), source: source, usedPasteboardFallback: false)
        }

        guard isAccessibilityTrusted else { throw SelectionCaptureError.accessibilityPermissionRequired }
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount
        try synthesizeCopy()
        try await Task.sleep(for: copyDelay)

        guard pasteboard.changeCount != initialChangeCount else {
            throw SelectionCaptureError.noSelection
        }
        let copyChangeCount = pasteboard.changeCount
        guard let payload = payload(from: pasteboard), !payload.isEmpty else {
            snapshot.restore(to: pasteboard, ifCurrentChangeCountIs: copyChangeCount)
            throw SelectionCaptureError.unsupportedSelection
        }
        snapshot.restore(to: pasteboard, ifCurrentChangeCountIs: copyChangeCount)
        return SelectionCaptureResult(payload: payload, source: source, usedPasteboardFallback: true)
    }

    private func currentSource() -> CaptureSource {
        let application = workspace.frontmostApplication
        var documentURL: URL?
        if let focused = focusedElement(), let document = attribute(kAXDocumentAttribute, from: focused) as? String {
            documentURL = URL(string: document)
        }
        return CaptureSource(
            applicationName: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier,
            documentURL: documentURL
        )
    }

    private func directlySelectedText() -> String? {
        guard isAccessibilityTrusted, let focused = focusedElement() else { return nil }
        return attribute(kAXSelectedTextAttribute, from: focused) as? String
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private func attribute(_ name: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func synthesizeCopy() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw SelectionCaptureError.couldNotSynthesizeCopy
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func payload(from pasteboard: NSPasteboard) -> CapturePayload? {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        if let fileURLs, !fileURLs.isEmpty { return .files(fileURLs) }

        if let data = pasteboard.data(forType: .png), !data.isEmpty {
            return .image(data, typeIdentifier: UTType.png.identifier)
        }
        if let data = pasteboard.data(forType: .tiff), !data.isEmpty {
            return .image(data, typeIdentifier: UTType.tiff.identifier)
        }

        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let url = URL(string: string), let scheme = url.scheme, !scheme.isEmpty {
                return .url(url)
            }
            return .text(string)
        }
        if let string = pasteboard.string(forType: .URL), let url = URL(string: string) {
            return .url(url)
        }
        return nil
    }
}

enum SelectionCaptureError: LocalizedError {
    case accessibilityPermissionRequired
    case couldNotSynthesizeCopy
    case noSelection
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to read or copy the current selection."
        case .couldNotSynthesizeCopy:
            "The Copy keyboard event could not be created."
        case .noSelection:
            "The frontmost application did not provide a selection."
        case .unsupportedSelection:
            "The selected content is not supported."
        }
    }
}

private struct PasteboardSnapshot {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard, ifCurrentChangeCountIs expectedChangeCount: Int) {
        // Do not overwrite a new copy made by the user while the fallback was in flight.
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.clearContents()
        let restoredItems: [NSPasteboardItem] = items.map { snapshot in
            let item = NSPasteboardItem()
            snapshot.values.forEach { item.setData($0.data, forType: $0.type) }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
