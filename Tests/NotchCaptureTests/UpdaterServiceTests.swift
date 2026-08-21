import Sparkle
import XCTest
@testable import NotchCapture

@MainActor
final class NotchUpdateUserDriverTests: XCTestCase {
    func testCheckingAndDownloadCancellationsAreOneShot() {
        let driver = NotchUpdateUserDriver()
        var notifications: [(NotchNotification, NotchNotificationDelivery)] = []
        var checkCancellations = 0
        var downloadCancellations = 0
        driver.onNotification = { notifications.append(($0, $1)) }

        driver.showUserInitiatedUpdateCheck { checkCancellations += 1 }
        XCTAssertEqual(notifications.last?.1, .immediate)
        XCTAssertEqual(notifications.last?.0.progress, .indeterminate)
        driver.performAction(NotchUpdateUserDriver.ActionID.cancelCheck)
        driver.performAction(NotchUpdateUserDriver.ActionID.cancelCheck)
        XCTAssertEqual(checkCancellations, 1)

        driver.showDownloadInitiated { downloadCancellations += 1 }
        driver.performAction(NotchUpdateUserDriver.ActionID.cancelDownload)
        driver.performAction(NotchUpdateUserDriver.ActionID.cancelDownload)
        XCTAssertEqual(downloadCancellations, 1)
    }

    func testInvalidDownloadLengthsStayFiniteAndClamped() throws {
        let driver = NotchUpdateUserDriver()
        var latest: NotchNotification?
        driver.onNotification = { notification, _ in latest = notification }

        driver.showDownloadInitiated {}
        driver.showDownloadDidReceiveExpectedContentLength(0)
        driver.showDownloadDidReceiveData(ofLength: 512)
        XCTAssertEqual(latest?.progress, .indeterminate)
        XCTAssertTrue(try XCTUnwrap(latest?.detail).contains("downloaded"))

        driver.showDownloadDidReceiveExpectedContentLength(100)
        XCTAssertEqual(latest?.progress.normalizedFraction, 1)
        driver.showDownloadDidReceiveData(ofLength: .max)
        XCTAssertEqual(latest?.progress.normalizedFraction, 1)
        XCTAssertTrue(try XCTUnwrap(latest?.detail).contains("100%"))
    }

    func testExtractionProgressClampsNonFiniteAndOutOfRangeValues() {
        let driver = NotchUpdateUserDriver()
        var latest: NotchNotification?
        driver.onNotification = { notification, _ in latest = notification }

        driver.showExtractionReceivedProgress(.nan)
        XCTAssertEqual(latest?.progress.normalizedFraction, 0)
        driver.showExtractionReceivedProgress(2)
        XCTAssertEqual(latest?.progress.normalizedFraction, 1)
    }

    func testPermissionReplyAndErrorRetryResolveOnlyOnce() async {
        let driver = NotchUpdateUserDriver()
        var retryCount = 0
        driver.onRetryRequested = { retryCount += 1 }

        let permissionTask = Task {
            await driver.show(SPUUpdatePermissionRequest(systemProfile: []))
        }
        await Task.yield()
        await Task.yield()
        driver.performAction(NotchUpdateUserDriver.ActionID.allowChecks)
        driver.performAction(NotchUpdateUserDriver.ActionID.declineChecks)
        let response = await permissionTask.value
        XCTAssertTrue(response.automaticUpdateChecks)
        XCTAssertEqual(response.automaticUpdateDownloading?.boolValue, false)
        XCTAssertFalse(response.sendSystemProfile)

        let errorTask = Task {
            await driver.showUpdaterError(NSError(
                domain: "NotchUpdateUserDriverTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Offline"]
            ))
        }
        await Task.yield()
        await Task.yield()
        driver.performAction(NotchUpdateUserDriver.ActionID.retry)
        driver.performAction(NotchUpdateUserDriver.ActionID.retry)
        await errorTask.value
        XCTAssertEqual(retryCount, 1)
    }

    func testFocusRepublishesCurrentContentImmediatelyAndTeardownIsIdempotent() {
        let driver = NotchUpdateUserDriver()
        var deliveries: [NotchNotificationDelivery] = []
        var dismissals = 0
        driver.onNotification = { _, delivery in deliveries.append(delivery) }
        driver.onDismissNotification = { _ in dismissals += 1 }

        driver.showDownloadInitiated {}
        driver.showUpdateInFocus()
        XCTAssertEqual(deliveries, [.backgroundUpdate, .immediate])

        driver.dismissUpdateInstallation()
        driver.dismissUpdateInstallation()
        XCTAssertEqual(dismissals, 1)
    }

    func testReadyDeliveryPreservesManualVersusAutomaticPriority() async {
        let automaticDriver = NotchUpdateUserDriver()
        var automaticDelivery: NotchNotificationDelivery?
        automaticDriver.onNotification = { _, delivery in automaticDelivery = delivery }
        let automaticChoice = Task { await automaticDriver.showReadyToInstallAndRelaunch() }
        await Task.yield()
        XCTAssertEqual(automaticDelivery, .whenIdle)
        automaticDriver.performAction(NotchUpdateUserDriver.ActionID.later)
        _ = await automaticChoice.value

        let manualDriver = NotchUpdateUserDriver()
        var manualDelivery: NotchNotificationDelivery?
        manualDriver.onNotification = { _, delivery in manualDelivery = delivery }
        manualDriver.showUserInitiatedUpdateCheck {}
        let manualChoice = Task { await manualDriver.showReadyToInstallAndRelaunch() }
        await Task.yield()
        XCTAssertEqual(manualDelivery, .immediate)
        manualDriver.performAction(NotchUpdateUserDriver.ActionID.restart)
        _ = await manualChoice.value
    }
}
