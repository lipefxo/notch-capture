import AppKit

enum LedgerRowKeyboardCommand: Equatable {
    /// Return activates the selected row: links open and text-backed rows
    /// enter editing. It is separate from Space so the two keys never drift.
    case activateSelection
    /// F2 enters the selected item's editor, including for link-only captures.
    case editSelection
    /// Shift-F10 opens the selected row's existing More Actions menu.
    case showActions
    case toggleCompletion
    case moveToTrash
    case moveSelectionUp
    case moveSelectionDown
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
        guard event.type == .keyDown, !event.isARepeat else { return nil }

        // Shift-F10 is the standard keyboard equivalent of a row context
        // menu. Keep it separate from the unmodified ledger shortcuts so a
        // user's regular F10 key remains available to the responder chain.
        if event.keyCode == 109, commandModifiers == .shift {
            return .showActions
        }

        // F2 is the familiar inline-edit command. Function is ignored here
        // because compact keyboards report Fn+F2 as the same F2 key event.
        if event.keyCode == 120, commandModifiers.isEmpty {
            return .editSelection
        }

        guard commandModifiers.isEmpty else { return nil }

        switch event.keyCode {
        case 36, 76:
            return .activateSelection
        case 49:
            return .toggleCompletion
        case 51, 117:
            return .moveToTrash
        case 126:
            return .moveSelectionUp
        case 125:
            return .moveSelectionDown
        default:
            return nil
        }
    }
}
