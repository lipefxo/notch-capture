import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater, following the
/// system-service ownership shape of `LoginItemService`.
@MainActor
final class UpdaterService {
    private let updaterController: SPUStandardUpdaterController?

    /// Sparkle requires a real app bundle: under `swift run` or
    /// `--design-preview` there is none, and starting the updater there
    /// presents an error dialog instead of failing quietly.
    init(previewMode: Bool) {
        if !previewMode, Bundle.main.bundleIdentifier == "com.lipe.notchcapture" {
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            self.updaterController = nil
        }
    }

    var isEnabled: Bool { updaterController != nil }

    func checkForUpdates() {
        guard let updaterController else { return }
        // Sparkle rejects a check made before its updater has completed its
        // startup cycle. A Settings click can race that cycle during launch;
        // calling through anyway raises an Objective-C exception and takes the
        // accessory app down instead of presenting the update UI.
        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
}
