import AppKit
import Carbon

struct ShortcutRecording {
    let definition: GlobalHotKeyDefinition
    let displayValue: String
}

@MainActor
enum ShortcutRecorder {
    static func capture(title: String, currentValue: String) -> ShortcutRecording? {
        var recording: ShortcutRecording?
        let alert = NSAlert()
        alert.messageText = "Record \(title)"
        alert.informativeText = "Press a shortcut that includes Control, Option, Shift, or Command. Press Escape to cancel."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")

        let recorder = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        recorder.currentValue = currentValue
        recorder.onCancel = {
            NSApp.abortModal()
        }
        recorder.onRecord = { value in
            recording = value
            NSApp.abortModal()
        }
        alert.accessoryView = recorder
        alert.window.initialFirstResponder = recorder

        NSApp.activate(ignoringOtherApps: true)
        _ = alert.runModal()
        return recording
    }
}

@MainActor
private final class ShortcutRecorderView: NSView {
    var currentValue = ""
    var onRecord: ((ShortcutRecording) -> Void)?
    var onCancel: (() -> Void)?
    private var validationMessage: String?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0, !isModifierOnly(event.keyCode) else {
            validationMessage = "Include a modifier and a regular key."
            NSSound.beep()
            needsDisplay = true
            return
        }

        let key = keyName(for: event)
        let display = modifierSymbols(modifiers) + key
        onRecord?(
            ShortcutRecording(
                definition: GlobalHotKeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers),
                displayValue: display
            )
        )
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let headline = "Type shortcut · currently \(currentValue)"
        headline.draw(
            at: NSPoint(x: 12, y: 31),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        (validationMessage ?? "The new shortcut is saved as soon as you press it.").draw(
            at: NSPoint(x: 12, y: 12),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: validationMessage == nil ? NSColor.secondaryLabelColor : NSColor.systemOrange,
            ]
        )
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private func modifierSymbols(_ modifiers: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value
    }

    private func keyName(for event: NSEvent) -> String {
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

    private func isModifierOnly(_ keyCode: UInt16) -> Bool {
        [kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option, kVK_Control,
         kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl]
            .contains(Int(keyCode))
    }
}
