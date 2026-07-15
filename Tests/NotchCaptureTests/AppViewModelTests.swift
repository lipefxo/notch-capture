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

    func testSelectedRowKeyboardCommandsToggleCompletionAndMoveToTrash() {
        var completedIDs: [UUID] = []
        var trashedIDs: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onToggleComplete = { completedIDs.append($0) }
        hooks.onTrash = { trashedIDs.append($0) }
        let item = AppViewModel.LedgerItem(title: "Review launch notes")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [item], hooks: hooks)

        viewModel.select(item)

        XCTAssertEqual(viewModel.keyboardFocus, .selectedRow)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertTrue(viewModel.items[0].isCompleted)
        XCTAssertEqual(completedIDs, [item.id])

        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertFalse(viewModel.items[0].isCompleted)
        XCTAssertEqual(completedIDs, [item.id, item.id])

        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.moveToTrash))
        XCTAssertTrue(viewModel.items[0].isTrashed)
        XCTAssertEqual(trashedIDs, [item.id])
        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertEqual(viewModel.keyboardFocus, .none)
    }

    func testSelectedRowKeyboardCommandsRespectComposerFocusAndTrashSafety() {
        var trashedIDs: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onTrash = { trashedIDs.append($0) }
        let activeItem = AppViewModel.LedgerItem(title: "Active task")
        let trashedItem = AppViewModel.LedgerItem(title: "Trashed task", isTrashed: true)
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [activeItem, trashedItem],
            hooks: hooks
        )

        XCTAssertFalse(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))

        viewModel.select(activeItem)
        viewModel.focusComposer()
        XCTAssertFalse(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertFalse(viewModel.items[0].isCompleted)

        viewModel.filter = .trash
        viewModel.select(trashedItem)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.moveToTrash))
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertTrue(viewModel.items[1].isTrashed)
        XCTAssertTrue(trashedIDs.isEmpty)
    }

    func testCompletedTasksRemainOnAllForTwentyFourHours() {
        let now = Date.now
        let openTask = AppViewModel.LedgerItem(kind: .task, title: "Open task")
        let recentlyCompleted = AppViewModel.LedgerItem(
            kind: .task,
            title: "Recently completed",
            createdAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
            isCompleted: true,
            completedAt: now.addingTimeInterval(-(23 * 60 * 60))
        )
        let expiredCompletion = AppViewModel.LedgerItem(
            kind: .task,
            title: "Completed yesterday",
            isCompleted: true,
            completedAt: now.addingTimeInterval(-(24 * 60 * 60))
        )
        let legacyCompletion = AppViewModel.LedgerItem(
            kind: .task,
            title: "Completion time unknown",
            isCompleted: true
        )
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [openTask, recentlyCompleted, expiredCompletion, legacyCompletion]
        )

        XCTAssertEqual(Set(viewModel.visibleItems.map(\.id)), Set([openTask.id, recentlyCompleted.id]))

        viewModel.filter = .completed

        XCTAssertEqual(
            Set(viewModel.visibleItems.map(\.id)),
            Set([recentlyCompleted.id, expiredCompletion.id, legacyCompletion.id])
        )
    }

    func testOnlyAttachmentItemsDisplayAPrefixIcon() {
        let textNote = AppViewModel.LedgerItem(title: "Text note")
        let textTask = AppViewModel.LedgerItem(kind: .task, title: "Text task")
        let attachment = AppViewModel.LedgerItem(
            title: "Reference",
            attachments: [.init(kind: .file, name: "brief.pdf")]
        )

        XCTAssertFalse(textNote.displaysAttachmentPrefix)
        XCTAssertFalse(textTask.displaysAttachmentPrefix)
        XCTAssertTrue(attachment.displaysAttachmentPrefix)
    }

    func testReorderWithinGroupPersistsNormalizedAssignments() {
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let second = AppViewModel.LedgerItem(title: "Second", sortOrder: 1)
        let third = AppViewModel.LedgerItem(title: "Third", sortOrder: 2)
        var persisted: [ItemOrderAssignment] = []
        var hooks = AppViewModel.Hooks()
        hooks.onReorder = { persisted = $0 }
        let viewModel = AppViewModel(items: [first, second, third], hooks: hooks)

        XCTAssertTrue(
            viewModel.reorder(
                itemID: third.id,
                relativeTo: first.id,
                placement: .before,
                destinationPinned: false
            )
        )

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(persisted.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(persisted.map(\.sortOrder), [0, 1, 2])
    }

    func testCrossGroupReorderPinsAtRequestedPosition() {
        let firstPinned = AppViewModel.LedgerItem(title: "First pinned", isPinned: true, sortOrder: 0)
        let secondPinned = AppViewModel.LedgerItem(title: "Second pinned", isPinned: true, sortOrder: 1)
        let unpinned = AppViewModel.LedgerItem(title: "Unpinned", sortOrder: 0)
        let viewModel = AppViewModel(items: [firstPinned, secondPinned, unpinned])

        XCTAssertTrue(
            viewModel.reorder(
                itemID: unpinned.id,
                relativeTo: secondPinned.id,
                placement: .before,
                destinationPinned: true
            )
        )

        XCTAssertEqual(viewModel.pinnedItems.map(\.id), [firstPinned.id, unpinned.id, secondPinned.id])
        XCTAssertTrue(viewModel.items.first(where: { $0.id == unpinned.id })?.isPinned == true)
        XCTAssertTrue(viewModel.unpinnedItems.isEmpty)
    }

    func testFilteredReorderUsesSharedOrderAndKeepsHiddenRowsRelative() {
        let taskA = AppViewModel.LedgerItem(kind: .task, title: "Task A", sortOrder: 0)
        let hiddenA = AppViewModel.LedgerItem(title: "Hidden A", sortOrder: 1)
        let hiddenB = AppViewModel.LedgerItem(title: "Hidden B", sortOrder: 2)
        let taskB = AppViewModel.LedgerItem(kind: .task, title: "Task B", sortOrder: 3)
        let viewModel = AppViewModel(items: [taskA, hiddenA, hiddenB, taskB])
        viewModel.filter = .tasks

        XCTAssertTrue(
            viewModel.reorder(
                itemID: taskB.id,
                relativeTo: taskA.id,
                placement: .before,
                destinationPinned: false
            )
        )
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [taskB.id, taskA.id])

        viewModel.filter = .all
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [taskB.id, taskA.id, hiddenA.id, hiddenB.id])
        let hiddenOrder = viewModel.visibleItems.filter { $0.id == hiddenA.id || $0.id == hiddenB.id }
        XCTAssertEqual(hiddenOrder.map(\.id), [hiddenA.id, hiddenB.id])
    }

    func testUnpinPlacesItemAtTopOfUnpinnedGroup() {
        let pinned = AppViewModel.LedgerItem(title: "Pinned", isPinned: true, sortOrder: 0)
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let second = AppViewModel.LedgerItem(title: "Second", sortOrder: 1)
        let viewModel = AppViewModel(items: [pinned, first, second])

        viewModel.togglePin(pinned)

        XCTAssertEqual(viewModel.unpinnedItems.map(\.id), [pinned.id, first.id, second.id])
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

    func testConfirmationPausesAndResumesWithRemainingTime() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 10_000)
        var pauseEvents: [(paused: Bool, remaining: TimeInterval)] = []
        var hooks = AppViewModel.Hooks()
        hooks.onConfirmationPauseChanged = { paused, remaining in
            pauseEvents.append((paused, remaining))
        }
        let viewModel = AppViewModel(
            surfaceState: .dormant,
            hooks: hooks,
            now: { currentDate }
        )

        viewModel.showConfirmation(for: AppViewModel.LedgerItem(title: "Selected text"))
        currentDate = currentDate.addingTimeInterval(2)
        viewModel.setConfirmationPaused(true)

        XCTAssertTrue(try XCTUnwrap(viewModel.confirmation).isPaused)
        XCTAssertEqual(try XCTUnwrap(viewModel.confirmation).remaining(at: currentDate), 3, accuracy: 0.001)

        currentDate = currentDate.addingTimeInterval(10)
        XCTAssertEqual(try XCTUnwrap(viewModel.confirmation).remaining(at: currentDate), 3, accuracy: 0.001)

        viewModel.setConfirmationPaused(false)
        let resumed = try XCTUnwrap(viewModel.confirmation)
        XCTAssertFalse(resumed.isPaused)
        XCTAssertEqual(resumed.expiresAt, currentDate.addingTimeInterval(3))
        XCTAssertEqual(pauseEvents.count, 2)
        XCTAssertTrue(pauseEvents[0].paused)
        XCTAssertFalse(pauseEvents[1].paused)
        XCTAssertEqual(pauseEvents[1].remaining, 3, accuracy: 0.001)
    }

    func testRepeatedConfirmationPauseRequestsAreIdempotent() throws {
        let date = Date(timeIntervalSinceReferenceDate: 20_000)
        var eventCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onConfirmationPauseChanged = { _, _ in eventCount += 1 }
        let viewModel = AppViewModel(
            surfaceState: .dormant,
            hooks: hooks,
            now: { date }
        )
        viewModel.showConfirmation(for: AppViewModel.LedgerItem(title: "Selected text"))

        viewModel.setConfirmationPaused(true)
        viewModel.setConfirmationPaused(true)

        XCTAssertEqual(eventCount, 1)
        XCTAssertTrue(try XCTUnwrap(viewModel.confirmation).isPaused)
    }

    func testRepeatedConfirmationResetsTheFiveSecondDeadline() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 30_000)
        let viewModel = AppViewModel(
            surfaceState: .dormant,
            now: { currentDate }
        )

        viewModel.showConfirmation(for: AppViewModel.LedgerItem(title: "First capture"))
        currentDate = currentDate.addingTimeInterval(4)
        viewModel.showConfirmation(for: AppViewModel.LedgerItem(title: "Second capture"))

        let confirmation = try XCTUnwrap(viewModel.confirmation)
        XCTAssertEqual(confirmation.title, "Second capture")
        XCTAssertEqual(confirmation.remaining(at: currentDate), 5, accuracy: 0.001)
    }
}
