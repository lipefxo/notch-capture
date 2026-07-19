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
        updaterController?.checkForUpdates(nil)
    }
}
