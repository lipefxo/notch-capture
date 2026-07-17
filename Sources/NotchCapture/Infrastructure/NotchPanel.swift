import AppKit

enum LedgerRowKeyboardCommand: Equatable {
    case toggleCompletion
    case moveToTrash
}

/// A panel that can switch between passive, non-key presentation and an active
/// composer without ever becoming the application's main window.
public final class NotchPanel: NSPanel {
    public var permitsKeyWindow = false
    var onLedgerRowKeyboardCommand: (@MainActor (LedgerRowKeyboardCommand) -> Bool)?
    var onComposerImagePaste: (@MainActor (NSPasteboard) -> Bool)?

    public override var canBecomeKey: Bool {
        permitsKeyWindow
    }

    public override var canBecomeMain: Bool {
        false
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = Self.editingAction(for: event) {
            if action == #selector(NSText.paste(_:)),
               onComposerImagePaste?(NSPasteboard.general) == true {
                return true
            }
            if NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func sendEvent(_ event: NSEvent) {
        if let command = Self.ledgerRowKeyboardCommand(for: event),
           onLedgerRowKeyboardCommand?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    static func editingAction(for event: NSEvent) -> Selector? {
        let editingModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard editingModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return nil
        }
        return #selector(NSText.paste(_:))
    }

    static func ledgerRowKeyboardCommand(for event: NSEvent) -> LedgerRowKeyboardCommand? {
        let commandModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.type == .keyDown, !event.isARepeat, commandModifiers.isEmpty else { return nil }

        switch event.keyCode {
        case 36, 49, 76:
            return .toggleCompletion
        case 51, 117:
            return .moveToTrash
        default:
            return nil
        }
    }
}
