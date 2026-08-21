import AppKit
import Sparkle

/// Sparkle user driver that maps the complete update lifecycle onto one stable
/// notch notification instead of allowing Sparkle to create native windows.
@MainActor
final class NotchUpdateUserDriver: NSObject, SPUUserDriver {
    nonisolated static let notificationID = "software-update"

    enum ActionID {
        static let allowChecks = "allow-checks"
        static let declineChecks = "decline-checks"
        static let cancelCheck = "cancel-check"
        static let install = "install"
        static let later = "later"
        static let learnMore = "learn-more"
        static let cancelDownload = "cancel-download"
        static let restart = "restart"
        static let retry = "retry"
        static let dismiss = "dismiss"
        static let retryQuit = "retry-quit"
        static let acknowledge = "acknowledge"
    }

    var onNotification: (NotchNotification, NotchNotificationDelivery) -> Void = { _, _ in }
    var onDismissNotification: (String) -> Void = { _ in }
    var onRetryRequested: () -> Void = {}

    private var currentNotification: NotchNotification?
    private var permissionContinuation: CheckedContinuation<SUUpdatePermissionResponse, Never>?
    private var choiceContinuation: CheckedContinuation<SPUUserUpdateChoice, Never>?
    private var acknowledgementContinuation: CheckedContinuation<Void, Never>?
    private var checkCancellation: (() -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var retryTermination: (() -> Void)?
    private var infoURL: URL?
    private var displayVersion: String?
    private var expectedContentLength: UInt64?
    private var receivedContentLength: UInt64 = 0
    private var userInitiated = false

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        resolvePermission(automaticChecks: false)
        let notification = NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.triangle.2.circlepath",
            tone: .neutral,
            title: "Keep Notch Capture up to date?",
            detail: "Check automatically each hour",
            secondaryAction: .init(
                id: ActionID.declineChecks,
                title: "Not Now",
                dismissesNotification: true
            ),
            primaryAction: .init(
                id: ActionID.allowChecks,
                title: "Allow",
                emphasis: .primary,
                dismissesNotification: true
            ),
            dismissalActionID: ActionID.declineChecks,
            accessibilityText: "Allow Notch Capture to check automatically for updates?"
        )
        publish(notification, delivery: .whenIdle)
        return await withCheckedContinuation { permissionContinuation = $0 }
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        checkCancellation = cancellation
        publish(checkingNotification(), delivery: .immediate)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        resolveChoice(.dismiss)
        checkCancellation = nil
        userInitiated = state.userInitiated
        displayVersion = appcastItem.displayVersionString
        infoURL = appcastItem.infoURL
        expectedContentLength = appcastItem.contentLength > 0 ? appcastItem.contentLength : nil
        receivedContentLength = 0

        let version = appcastItem.displayVersionString
        let detail = updateSizeDetail(appcastItem.contentLength)
        let notification: NotchNotification
        if appcastItem.isInformationOnlyUpdate {
            notification = NotchNotification(
                id: Self.notificationID,
                systemImage: "info",
                tone: .neutral,
                title: "Notch Capture \(version) is available",
                detail: "Learn more before updating",
                secondaryAction: laterAction,
                primaryAction: .init(
                    id: ActionID.learnMore,
                    title: "Learn More",
                    emphasis: .primary
                ),
                dismissalActionID: ActionID.later,
                accessibilityText: "Notch Capture version \(version) is available. Information only update."
            )
        } else {
            switch state.stage {
            case .notDownloaded:
                notification = availableNotification(version: version, detail: detail)
            case .downloaded:
                notification = readyNotification(version: version)
            case .installing:
                notification = readyNotification(version: version)
            @unknown default:
                notification = availableNotification(version: version, detail: detail)
            }
        }
        publish(notification, delivery: state.userInitiated ? .immediate : .whenIdle)
        return await withCheckedContinuation { choiceContinuation = $0 }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Option 1 intentionally has no release-note region.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // Release notes are not presented, so this does not alter update state.
    }

    func showUpdateNotFoundWithError(_ error: any Error) async {
        checkCancellation = nil
        let nsError = error as NSError
        let reason = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        let isCurrent = reason == Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue)
            || reason == Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue)
        if isCurrent {
            let notification = NotchNotification(
                id: Self.notificationID,
                systemImage: "checkmark",
                tone: .positive,
                title: "Notch Capture is up to date",
                detail: "You’re running the latest available version",
                dismissalActionID: ActionID.acknowledge,
                accessibilityText: "Notch Capture is up to date.",
                autoDismissAfter: 3,
                autoDismissActionID: ActionID.acknowledge
            )
            publish(notification, delivery: .immediate)
        } else {
            publish(errorNotification(
                title: "No compatible update found",
                detail: conciseErrorDetail(nsError)
            ), delivery: .immediate)
        }
        await waitForAcknowledgement()
    }

    func showUpdaterError(_ error: any Error) async {
        checkCancellation = nil
        downloadCancellation = nil
        publish(errorNotification(
            title: "Update couldn’t be completed",
            detail: conciseErrorDetail(error as NSError)
        ), delivery: userInitiated ? .immediate : .whenIdle)
        await waitForAcknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        expectedContentLength = nil
        receivedContentLength = 0
        publish(downloadingNotification(), delivery: .backgroundUpdate)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength > 0 ? expectedContentLength : nil
        publish(downloadingNotification(), delivery: .backgroundUpdate)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let result = receivedContentLength.addingReportingOverflow(length)
        receivedContentLength = result.overflow ? UInt64.max : result.partialValue
        publish(downloadingNotification(), delivery: .backgroundUpdate)
    }

    func showDownloadDidStartExtractingUpdate() {
        downloadCancellation = nil
        publish(NotchNotification(
            id: Self.notificationID,
            systemImage: "shippingbox",
            tone: .neutral,
            title: "Preparing Notch Capture \(displayVersion ?? "update")",
            detail: "Extracting update…",
            progress: .indeterminate,
            accessibilityText: "Preparing the Notch Capture update. Extracting."
        ), delivery: .backgroundUpdate)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        let normalized = progress.isFinite ? min(max(progress, 0), 1) : 0
        publish(NotchNotification(
            id: Self.notificationID,
            systemImage: "shippingbox",
            tone: .neutral,
            title: "Preparing Notch Capture \(displayVersion ?? "update")",
            detail: "Extracting… \(Int((normalized * 100).rounded()))%",
            progress: .fraction(normalized),
            accessibilityText: "Preparing the Notch Capture update. \(Int((normalized * 100).rounded())) percent extracted."
        ), delivery: .backgroundUpdate)
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        resolveChoice(.dismiss)
        downloadCancellation = nil
        publish(
            readyNotification(version: displayVersion),
            delivery: userInitiated ? .immediate : .whenIdle
        )
        return await withCheckedContinuation { choiceContinuation = $0 }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        publish(NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.triangle.2.circlepath",
            tone: .neutral,
            title: "Installing Notch Capture \(displayVersion ?? "update")",
            detail: applicationTerminated ? "Finishing installation…" : "Waiting for Notch Capture to quit…",
            progress: .indeterminate,
            primaryAction: applicationTerminated ? nil : .init(
                id: ActionID.retryQuit,
                title: "Retry Quit",
                emphasis: .primary
            ),
            accessibilityText: applicationTerminated
                ? "Installing the Notch Capture update."
                : "Waiting for Notch Capture to quit before installing."
        ), delivery: .backgroundUpdate)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        publish(NotchNotification(
            id: Self.notificationID,
            systemImage: "checkmark",
            tone: .positive,
            title: "Notch Capture is updated",
            detail: relaunched ? "The latest version is ready" : "Update installed successfully",
            dismissalActionID: ActionID.acknowledge,
            accessibilityText: "Notch Capture updated successfully.",
            autoDismissAfter: 3,
            autoDismissActionID: ActionID.acknowledge
        ), delivery: userInitiated ? .immediate : .whenIdle)
        await waitForAcknowledgement()
    }

    func dismissUpdateInstallation() {
        let hadActiveSession = currentNotification != nil
            || permissionContinuation != nil
            || choiceContinuation != nil
            || acknowledgementContinuation != nil
            || checkCancellation != nil
            || downloadCancellation != nil
            || retryTermination != nil
        checkCancellation = nil
        downloadCancellation = nil
        retryTermination = nil
        resolvePermission(automaticChecks: false)
        resolveChoice(.dismiss)
        resolveAcknowledgement()
        currentNotification = nil
        if hadActiveSession { onDismissNotification(Self.notificationID) }
    }

    func showUpdateInFocus() {
        guard let currentNotification else { return }
        publish(currentNotification, delivery: .immediate)
    }

    func performAction(_ actionID: String) {
        switch actionID {
        case ActionID.allowChecks:
            resolvePermission(automaticChecks: true)
        case ActionID.declineChecks:
            resolvePermission(automaticChecks: false)
        case ActionID.cancelCheck:
            take(&checkCancellation)?()
        case ActionID.install, ActionID.restart:
            resolveChoice(.install)
        case ActionID.later:
            resolveChoice(.dismiss)
        case ActionID.learnMore:
            if resolveChoice(.dismiss), let infoURL { NSWorkspace.shared.open(infoURL) }
        case ActionID.cancelDownload:
            take(&downloadCancellation)?()
        case ActionID.retry:
            if resolveAcknowledgement() { onRetryRequested() }
        case ActionID.dismiss, ActionID.acknowledge:
            resolveAcknowledgement()
        case ActionID.retryQuit:
            take(&retryTermination)?()
        default:
            break
        }
    }

    private var laterAction: NotchNotification.Action {
        .init(id: ActionID.later, title: "Later", dismissesNotification: true)
    }

    private func checkingNotification() -> NotchNotification {
        NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.triangle.2.circlepath",
            tone: .neutral,
            title: "Checking for updates…",
            detail: "Looking for the latest Notch Capture version",
            progress: .indeterminate,
            primaryAction: .init(
                id: ActionID.cancelCheck,
                title: "Cancel",
                emphasis: .primary,
                dismissesNotification: true
            ),
            dismissalActionID: ActionID.cancelCheck,
            accessibilityText: "Checking for Notch Capture updates."
        )
    }

    private func availableNotification(version: String, detail: String) -> NotchNotification {
        NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.down",
            tone: .neutral,
            title: "Notch Capture \(version) is available",
            detail: detail,
            secondaryAction: laterAction,
            primaryAction: .init(id: ActionID.install, title: "Update", emphasis: .primary),
            dismissalActionID: ActionID.later,
            accessibilityText: "Notch Capture version \(version) is available. \(detail)."
        )
    }

    private func readyNotification(version: String?) -> NotchNotification {
        let versionText = version.map { " \($0)" } ?? ""
        return NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.clockwise",
            tone: .positive,
            title: "Notch Capture\(versionText) is ready",
            detail: "Restart to finish installing the update",
            secondaryAction: laterAction,
            primaryAction: .init(id: ActionID.restart, title: "Restart", emphasis: .primary),
            dismissalActionID: ActionID.later,
            accessibilityText: "The Notch Capture update is ready. Restart to install."
        )
    }

    private func downloadingNotification() -> NotchNotification {
        let progress: NotchNotification.Progress
        let detail: String
        if let expectedContentLength, expectedContentLength > 0 {
            let fraction = min(Double(receivedContentLength) / Double(expectedContentLength), 1)
            progress = .fraction(fraction)
            detail = "\(Int((fraction * 100).rounded()))% · \(formatBytes(receivedContentLength)) of \(formatBytes(expectedContentLength))"
        } else {
            progress = .indeterminate
            detail = receivedContentLength > 0
                ? "\(formatBytes(receivedContentLength)) downloaded"
                : "Starting download…"
        }
        return NotchNotification(
            id: Self.notificationID,
            systemImage: "arrow.down",
            tone: .neutral,
            title: "Downloading Notch Capture \(displayVersion ?? "update")",
            detail: detail,
            progress: progress,
            primaryAction: .init(
                id: ActionID.cancelDownload,
                title: "Cancel",
                emphasis: .primary,
                dismissesNotification: true
            ),
            accessibilityText: "Downloading the Notch Capture update. \(detail)."
        )
    }

    private func errorNotification(title: String, detail: String) -> NotchNotification {
        NotchNotification(
            id: Self.notificationID,
            systemImage: "exclamationmark",
            tone: .error,
            title: title,
            detail: detail,
            secondaryAction: .init(
                id: ActionID.dismiss,
                title: "Dismiss",
                dismissesNotification: true
            ),
            primaryAction: .init(id: ActionID.retry, title: "Retry", emphasis: .primary),
            dismissalActionID: ActionID.dismiss,
            accessibilityText: "\(title). \(detail)."
        )
    }

    private func publish(
        _ notification: NotchNotification,
        delivery: NotchNotificationDelivery
    ) {
        currentNotification = notification
        onNotification(notification, delivery)
    }

    private func waitForAcknowledgement() async {
        resolveAcknowledgement()
        await withCheckedContinuation { acknowledgementContinuation = $0 }
    }

    @discardableResult
    private func resolvePermission(automaticChecks: Bool) -> Bool {
        guard let continuation = take(&permissionContinuation) else { return false }
        continuation.resume(returning: SUUpdatePermissionResponse(
            automaticUpdateChecks: automaticChecks,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
        return true
    }

    @discardableResult
    private func resolveChoice(_ choice: SPUUserUpdateChoice) -> Bool {
        guard let continuation = take(&choiceContinuation) else { return false }
        continuation.resume(returning: choice)
        return true
    }

    @discardableResult
    private func resolveAcknowledgement() -> Bool {
        guard let continuation = take(&acknowledgementContinuation) else { return false }
        continuation.resume()
        return true
    }

    private func updateSizeDetail(_ byteCount: UInt64) -> String {
        byteCount > 0 ? "\(formatBytes(byteCount)) update" : "Update available"
    }

    private func formatBytes(_ byteCount: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount > UInt64(Int64.max) ? Int64.max : Int64(byteCount),
            countStyle: .file
        )
    }

    private func conciseErrorDetail(_ error: NSError) -> String {
        let detail = error.localizedRecoverySuggestion ?? error.localizedDescription
        return detail.replacingOccurrences(of: "\n", with: " ")
    }

    private func take<T>(_ value: inout T?) -> T? {
        defer { value = nil }
        return value
    }
}
