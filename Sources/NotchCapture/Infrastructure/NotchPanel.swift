import AppKit

/// A panel that can switch between passive, non-key presentation and an active
/// composer without ever becoming the application's main window.
public final class NotchPanel: NSPanel {
    public var permitsKeyWindow = false

    public override var canBecomeKey: Bool {
        permitsKeyWindow
    }

    public override var canBecomeMain: Bool {
        false
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = Self.editingAction(for: event),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func editingAction(for event: NSEvent) -> Selector? {
        let editingModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard editingModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return nil
        }
        return #selector(NSText.paste(_:))
    }
}
