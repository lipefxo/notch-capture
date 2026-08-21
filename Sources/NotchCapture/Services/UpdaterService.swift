import Sparkle

/// Owns Sparkle directly so all user interaction is routed through the notch.
@MainActor
final class UpdaterService {
    var onNotification: (NotchNotification, NotchNotificationDelivery) -> Void = { _, _ in }
    var onDismissNotification: (String) -> Void = { _ in }
    var onEnabledChange: (Bool) -> Void = { _ in }

    private let updater: SPUUpdater?
    private let userDriver: NotchUpdateUserDriver?
    private var started = false
    private var retryTask: Task<Void, Never>?

    /// Sparkle requires a real app bundle: under `swift run` or
    /// `--design-preview` there is none, and starting the updater there
    /// presents an error dialog instead of failing quietly.
    init(previewMode: Bool) {
        if !previewMode, Bundle.main.bundleIdentifier == "com.lipe.notchcapture" {
            let userDriver = NotchUpdateUserDriver()
            self.userDriver = userDriver
            self.updater = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: userDriver,
                delegate: nil
            )
        } else {
            self.userDriver = nil
            self.updater = nil
        }

        userDriver?.onNotification = { [weak self] notification, delivery in
            self?.onNotification(notification, delivery)
        }
        userDriver?.onDismissNotification = { [weak self] id in
            self?.onDismissNotification(id)
        }
        userDriver?.onRetryRequested = { [weak self] in
            self?.retryWhenAvailable()
        }
    }

    var isEnabled: Bool { updater != nil }

    /// Startup is intentionally separate from initialization: AppCoordinator
    /// connects notification callbacks first, so Sparkle startup events cannot
    /// race the host.
    func start() {
        guard let updater, !started else { return }
        do {
            try updater.start()
            started = true
            onEnabledChange(true)
        } catch {
            onEnabledChange(false)
            onNotification(
                NotchNotification(
                    id: NotchUpdateUserDriver.notificationID,
                    systemImage: "exclamationmark",
                    tone: .error,
                    title: "Updates aren’t available",
                    detail: error.localizedDescription,
                    secondaryAction: .init(
                        id: NotchUpdateUserDriver.ActionID.dismiss,
                        title: "Dismiss",
                        dismissesNotification: true
                    ),
                    dismissalActionID: NotchUpdateUserDriver.ActionID.dismiss,
                    accessibilityText: "Notch Capture updates are not available. \(error.localizedDescription)"
                ),
                .whenIdle
            )
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        userDriver?.dismissUpdateInstallation()
    }

    func checkForUpdates() {
        guard let updater, started else { return }
        // Sparkle rejects a check made before its updater has completed its
        // startup cycle. A Settings click can race that cycle during launch;
        // calling through anyway raises an Objective-C exception and takes the
        // accessory app down instead of presenting the update UI.
        guard updater.canCheckForUpdates else {
            userDriver?.showUpdateInFocus()
            return
        }
        updater.checkForUpdates()
    }

    func performNotificationAction(notificationID: String, actionID: String) {
        guard notificationID == NotchUpdateUserDriver.notificationID else { return }
        userDriver?.performAction(actionID)
    }

    private func retryWhenAvailable() {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if self.updater?.canCheckForUpdates == true {
                    self.checkForUpdates()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
