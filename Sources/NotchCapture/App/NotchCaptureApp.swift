import AppKit

@main
@MainActor
enum NotchCaptureApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = NotchCaptureAppDelegate()
        application.delegate = delegate
        application.run()
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
