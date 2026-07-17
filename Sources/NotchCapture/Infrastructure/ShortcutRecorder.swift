import AppKit
import Carbon
import SwiftUI

struct ShortcutRecording {
    let definition: GlobalHotKeyDefinition
    let displayValue: String
}

enum ShortcutRecordingFailure: Error {
    case validation(String)

    var message: String {
        switch self { case let .validation(message): message }
    }
}

enum ShortcutRecorder {
    static func recording(for event: NSEvent) -> Result<ShortcutRecording, ShortcutRecordingFailure> {
        if isModifierOnly(event.keyCode) || carbonModifiers(from: event.modifierFlags) == 0 {
            return .failure(.validation("Include a modifier and a regular key."))
        }
        let modifiers = carbonModifiers(from: event.modifierFlags)
        return .success(ShortcutRecording(
            definition: GlobalHotKeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers),
            displayValue: modifierSymbols(modifiers) + keyName(for: event)
        ))
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func modifierSymbols(_ modifiers: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value
    }

    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let value = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            return value.isEmpty ? "Key \(event.keyCode)" : value
        }
    }

    private static func isModifierOnly(_ keyCode: UInt16) -> Bool {
        [kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option, kVK_Control,
         kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl].contains(Int(keyCode))
    }
}

struct ShortcutCaptureField: NSViewRepresentable {
    let currentValue: String
    let onRecording: (Result<ShortcutRecording, ShortcutRecordingFailure>) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.currentValue = currentValue
        view.onRecording = onRecording
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.currentValue = currentValue
        nsView.onRecording = onRecording
        nsView.onCancel = onCancel
    }
}

final class ShortcutCaptureNSView: NSView {
    var currentValue = "" { didSet { needsDisplay = true } }
    var onRecording: ((Result<ShortcutRecording, ShortcutRecordingFailure>) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        onRecording?(ShortcutRecorder.recording(for: event))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.stroke()
        (currentValue.isEmpty ? "Press keys…" : currentValue).draw(
            in: bounds.insetBy(dx: 10, dy: 8),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        )
    }
}
