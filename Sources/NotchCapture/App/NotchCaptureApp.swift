import AppKit

@main
@MainActor
enum NotchCaptureApplication {
    static func main() {
        let application = NSApplication.shared
        application.mainMenu = ApplicationMenuFactory.makeMainMenu()
        let delegate = NotchCaptureAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
enum ApplicationMenuFactory {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Notch Capture")
        applicationMenu.addItem(
            NSMenuItem(
                title: "Quit Notch Capture",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(command("Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(command("Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(command("Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(command("Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(command("Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(command("Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func command(
        _ title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        return item
    }
}

@MainActor
final class NotchCaptureAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let coordinator = try AppCoordinator()
            self.coordinator = coordinator
            coordinator.start()
        } catch {
            FileHandle.standardError.write(Data("Notch Capture startup failed: \(error.localizedDescription)\n".utf8))
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Notch Capture couldn’t start"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
