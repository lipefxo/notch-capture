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
}
