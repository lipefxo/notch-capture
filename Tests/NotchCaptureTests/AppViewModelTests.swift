import XCTest
@testable import NotchCapture

@MainActor
final class AppViewModelTests: XCTestCase {
    func testCreationTimestampIsAbsoluteAndOmitsElapsedUnits() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = 16
        components.minute = 59
        components.second = 23
        let date = try XCTUnwrap(components.date)

        let label = CaptureTimestampFormatter.string(
            from: date,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )

        XCTAssertEqual(label, "Jul 15, 4:59 PM")
        XCTAssertFalse(label.localizedCaseInsensitiveContains("sec"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("min"))
    }

    func testUnifiedInputFiltersMatchingItemsInsteadOfCapturing() {
        var captured: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { captured.append($0) }
        let matchingItem = AppViewModel.LedgerItem(title: "Book studio time")
        let otherItem = AppViewModel.LedgerItem(title: "Review launch notes")
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [matchingItem, otherItem],
            hooks: hooks
        )

        viewModel.composerText = "studio"

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [matchingItem.id])
        XCTAssertTrue(viewModel.composerHasMatches)
        XCTAssertFalse(viewModel.canAddComposerText)

        viewModel.submitComposer()

        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(viewModel.selectedItemID, matchingItem.id)
        XCTAssertEqual(viewModel.composerText, "studio")
    }

    func testUnifiedInputCapturesWhenNoItemMatches() {
        var captured: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { captured.append($0) }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [AppViewModel.LedgerItem(title: "Review launch notes")],
            hooks: hooks
        )
        viewModel.filter = .tasks
        viewModel.composerText = "Plan launch retrospective"

        XCTAssertTrue(viewModel.canAddComposerText)

        viewModel.submitComposer()

        XCTAssertEqual(captured, ["Plan launch retrospective"])
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertEqual(viewModel.surfaceState, .expanded)
    }

    func testManualCaptureFeedbackKeepsExpandedSessionOpenUntilDismissed() {
        let item = AppViewModel.LedgerItem(title: "A thought worth keeping")
        let viewModel = AppViewModel(surfaceState: .expanded)

        viewModel.showCaptureFeedback(for: item, feedback: .stayExpanded)

        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertNil(viewModel.confirmation)

        viewModel.dismiss()

        XCTAssertEqual(viewModel.surfaceState, .collapsed)
    }

    func testSilentCaptureStillUsesTransientConfirmation() {
        let item = AppViewModel.LedgerItem(title: "Selected text")
        let viewModel = AppViewModel(surfaceState: .dormant)

        viewModel.showCaptureFeedback(for: item, feedback: .transientConfirmation)

        XCTAssertEqual(viewModel.surfaceState, .confirmation)
        XCTAssertEqual(viewModel.confirmation?.itemID, item.id)
    }
}
