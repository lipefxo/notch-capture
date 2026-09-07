import XCTest
@testable import NotchCapture

@MainActor
final class RecoveryKeyboardTests: XCTestCase {
    func testSelectingGlobalFilterRoutesToRootAndClearsRouteState() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let item = AppViewModel.LedgerItem(
            title: "A task",
            folderID: folder.id,
            folderName: folder.name
        )
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [item],
            folders: [folder]
        )

        viewModel.openFolder(folder)
        viewModel.select(item)
        viewModel.composerText = "draft"

        XCTAssertTrue(viewModel.selectInboxFilter(.trash))
        XCTAssertEqual(viewModel.filter, .trash)
        XCTAssertEqual(viewModel.browseLocation, .root)
        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertNil(viewModel.selectedFolderID)
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
        XCTAssertTrue(viewModel.composerSearchesAllFolders)
    }

    func testFilterSelectionLeavesAnUnsavedEditorInPlaceWhenSaveFails() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let item = AppViewModel.LedgerItem(title: "Draft", folderID: folder.id)
        var hooks = AppViewModel.Hooks()
        hooks.onUpdateText = { _, _ in "Could not save the draft." }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [item],
            folders: [folder],
            hooks: hooks
        )

        viewModel.openFolder(folder)
        viewModel.beginEditing(item)
        viewModel.updateEditingDraft("Changed")

        XCTAssertFalse(viewModel.selectInboxFilter(.tasks))
        XCTAssertEqual(viewModel.browseLocation, .folder(folder.id))
        XCTAssertEqual(viewModel.filter, .all)
        XCTAssertEqual(viewModel.itemEditSession?.draft, "Changed")
        XCTAssertEqual(viewModel.errorMessage, "Could not save the draft.")
    }

    func testSelectionIsReconciledWhenFilterHidesTheCurrentItem() {
        let note = AppViewModel.LedgerItem(title: "Note")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [note])

        viewModel.select(note)
        viewModel.filter = .tasks

        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
    }

    func testKeyboardNavigationSkipsFoldersWhileFolderSectionIsCollapsed() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let inboxItem = AppViewModel.LedgerItem(title: "Inbox item")
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [inboxItem],
            folders: [folder]
        )

        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertNil(viewModel.selectedFolderID)
        XCTAssertEqual(viewModel.selectedItemID, inboxItem.id)
    }

    func testCollapsingFolderSectionClearsASelectedFolder() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            folders: [folder],
            isFolderSectionExpanded: true
        )

        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedFolderID, folder.id)

        viewModel.isFolderSectionExpanded = false

        XCTAssertNil(viewModel.selectedFolderID)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
        XCTAssertFalse(viewModel.moveLedgerSelection(by: -1))
    }

    func testGlobalFiltersSearchItemsAcrossFolders() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let open = AppViewModel.LedgerItem(
            kind: .task,
            title: "Open",
            folderID: folder.id,
            folderName: folder.name
        )
        let done = AppViewModel.LedgerItem(
            kind: .task,
            title: "Done",
            folderID: folder.id,
            folderName: folder.name,
            isCompleted: true,
            completedAt: .now
        )
        let archived = AppViewModel.LedgerItem(
            title: "Archived",
            folderID: folder.id,
            folderName: folder.name,
            isArchived: true
        )
        let trashed = AppViewModel.LedgerItem(
            title: "Trashed",
            folderID: folder.id,
            folderName: folder.name,
            isTrashed: true
        )
        let viewModel = AppViewModel(
            items: [open, done, archived, trashed],
            folders: [folder]
        )

        let expected: [(AppViewModel.InboxFilter, UUID)] = [
            (.tasks, open.id),
            (.completed, done.id),
            (.archive, archived.id),
            (.trash, trashed.id),
        ]
        for (filter, id) in expected {
            XCTAssertTrue(viewModel.selectInboxFilter(filter))
            XCTAssertEqual(viewModel.visibleItems.map(\.id), [id], "Filter: \(filter)")
        }
    }

    func testFolderSearchScopeBroadensExplicitlyAndResetsOnNavigation() {
        let work = AppViewModel.FolderSummary(name: "Work")
        let personal = AppViewModel.FolderSummary(name: "Personal", sortOrder: 1)
        let workItem = AppViewModel.LedgerItem(
            title: "Shared",
            folderID: work.id,
            folderName: work.name
        )
        let personalItem = AppViewModel.LedgerItem(
            title: "Shared",
            folderID: personal.id,
            folderName: personal.name
        )
        let viewModel = AppViewModel(items: [workItem, personalItem], folders: [work, personal])

        viewModel.openFolder(work)
        viewModel.composerText = "Shared"
        XCTAssertFalse(viewModel.composerSearchesAllFolders)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [workItem.id])

        viewModel.composerSearchesAllFolders = true
        XCTAssertEqual(Set(viewModel.visibleItems.map(\.id)), Set([workItem.id, personalItem.id]))
        XCTAssertTrue(viewModel.isShowingGlobalSearchResults)

        viewModel.openFolder(work)
        XCTAssertFalse(viewModel.composerSearchesAllFolders)
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testSlashPrefixEntersCommandModeAndLiteralSlashEscapesIt() {
        let item = AppViewModel.LedgerItem(title: "/foo")
        let viewModel = AppViewModel(items: [item])

        viewModel.composerText = "/fo"
        XCTAssertTrue(viewModel.isComposerCommandMode)
        XCTAssertFalse(viewModel.composerHasQuery)
        XCTAssertEqual(viewModel.composerCommandSuggestions, [.folder])

        viewModel.composerText = "//foo"
        XCTAssertFalse(viewModel.isComposerCommandMode)
        XCTAssertTrue(viewModel.composerHasQuery)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [item.id])
    }

    func testLiteralSlashEscapeIsRemovedBeforeCapture() {
        var captured: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in captured.append(text) }
        let viewModel = AppViewModel(hooks: hooks)

        viewModel.composerText = "//foo"
        XCTAssertTrue(viewModel.canAddComposerText)
        viewModel.submitComposer()

        XCTAssertEqual(captured, ["/foo"])
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testReturnActivatesLinkOnlyAndEditsTextBackedRows() throws {
        let linkURL = try XCTUnwrap(URL(string: "https://example.com"))
        let link = AppViewModel.LedgerItem(
            title: "Example",
            text: "",
            attachments: [.init(kind: .link, name: "Example", previewURL: linkURL)]
        )
        let noteWithLink = AppViewModel.LedgerItem(
            title: "Read this",
            text: "Read this later",
            attachments: [.init(kind: .link, name: "Example", previewURL: linkURL)]
        )
        var opened: [URL] = []
        var hooks = AppViewModel.Hooks()
        hooks.onOpenLink = { opened.append($0) }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [link, noteWithLink],
            hooks: hooks
        )

        viewModel.select(link)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.activateSelection))
        XCTAssertEqual(opened, [linkURL])
        XCTAssertNil(viewModel.itemEditSession)

        viewModel.select(noteWithLink)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.activateSelection))
        XCTAssertEqual(opened, [linkURL])
        XCTAssertEqual(viewModel.itemEditSession?.itemID, noteWithLink.id)
    }

    func testSpaceCompletesSelectedTaskWhileReturnEntersEditing() {
        let task = AppViewModel.LedgerItem(kind: .task, title: "Ship it")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [task])

        viewModel.select(task)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertTrue(viewModel.items[0].isCompleted)

        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.activateSelection))
        XCTAssertEqual(viewModel.itemEditSession?.itemID, task.id)
    }

    func testArchiveUndoKeepsLaterTextAndFolderEdits() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let item = AppViewModel.LedgerItem(title: "Original")
        let viewModel = AppViewModel(items: [item], folders: [folder])

        viewModel.archive(item)
        viewModel.beginEditing(viewModel.items[0])
        viewModel.updateEditingDraft("Edited after archive")
        XCTAssertTrue(viewModel.saveEditing())
        viewModel.move(viewModel.items[0], to: folder.id)

        XCTAssertTrue(viewModel.undoLastLedgerAction())
        let restored = viewModel.items[0]
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.text, "Edited after archive")
        XCTAssertEqual(restored.folderID, folder.id)
    }

    func testTrashUndoPreservesCompletionAndDoesNotRestoreStaleArchiveState() {
        let item = AppViewModel.LedgerItem(
            kind: .task,
            title: "Done",
            isCompleted: true,
            completedAt: .now
        )
        let viewModel = AppViewModel(items: [item])

        viewModel.trash(item)
        XCTAssertTrue(viewModel.items[0].isTrashed)
        XCTAssertTrue(viewModel.undoLastLedgerAction())
        XCTAssertFalse(viewModel.items[0].isTrashed)
        XCTAssertTrue(viewModel.items[0].isCompleted)
        XCTAssertTrue(viewModel.items[0].completedAt != nil)
    }

    func testClearUndoRestoresOnlyTrashBitForEveryCompletedTask() {
        let archived = AppViewModel.LedgerItem(
            kind: .task,
            title: "Archived done",
            isCompleted: true,
            completedAt: .now,
            isArchived: true
        )
        let ordinary = AppViewModel.LedgerItem(
            kind: .task,
            title: "Ordinary done",
            isCompleted: true,
            completedAt: .now
        )
        let viewModel = AppViewModel(items: [archived, ordinary])

        viewModel.clearCompletedTasks()
        viewModel.items[1].title = "Edited after clear"
        viewModel.items[1].text = "Edited after clear"

        XCTAssertTrue(viewModel.undoLastLedgerAction())
        XCTAssertFalse(viewModel.items[0].isTrashed)
        XCTAssertTrue(viewModel.items[0].isArchived)
        XCTAssertFalse(viewModel.items[1].isTrashed)
        XCTAssertEqual(viewModel.items[1].title, "Edited after clear")
    }

    func testRestorePreservesCompletedStateWhileMarkIncompleteRemainsExplicit() {
        let item = AppViewModel.LedgerItem(
            kind: .task,
            title: "Finished capture",
            isCompleted: true,
            completedAt: .now,
            isTrashed: true
        )
        var restoredIDs: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onRestore = { restoredIDs.append($0) }
        let viewModel = AppViewModel(items: [item], hooks: hooks)

        viewModel.restore(item)

        let restored = viewModel.items[0]
        XCTAssertFalse(restored.isTrashed)
        XCTAssertFalse(restored.isArchived)
        XCTAssertTrue(restored.isCompleted)
        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(restoredIDs, [item.id])
    }

    func testUndoPersistenceFailureKeepsActionAvailable() throws {
        var hooks = AppViewModel.Hooks()
        hooks.onUndoLedgerAction = { _ in "Could not save the undo." }
        let item = AppViewModel.LedgerItem(title: "Keep")
        let viewModel = AppViewModel(items: [item], hooks: hooks)

        viewModel.archive(item)
        XCTAssertFalse(viewModel.undoLastLedgerAction())
        XCTAssertTrue(viewModel.items[0].isArchived)
        XCTAssertEqual(viewModel.undoLedgerActionTitle, "Undo archive")
        XCTAssertEqual(viewModel.errorMessage, "Could not save the undo.")
        XCTAssertTrue(try XCTUnwrap(viewModel.pendingLedgerUndo).isPaused)
    }

    func testArchiveAndTrashHookFailuresDiscardOptimisticUndo() {
        let archiveItem = AppViewModel.LedgerItem(title: "Archive me")
        var archiveViewModel: AppViewModel!
        var archiveHooks = AppViewModel.Hooks()
        archiveHooks.onArchive = { _ in
            archiveViewModel.discardPendingLedgerUndo()
        }
        archiveViewModel = AppViewModel(items: [archiveItem], hooks: archiveHooks)
        archiveViewModel.archive(archiveItem)
        XCTAssertFalse(archiveViewModel.canUndoLedgerAction)

        let trashItem = AppViewModel.LedgerItem(title: "Trash me")
        var trashViewModel: AppViewModel!
        var trashHooks = AppViewModel.Hooks()
        trashHooks.onTrash = { _ in
            trashViewModel.discardPendingLedgerUndo()
        }
        trashViewModel = AppViewModel(items: [trashItem], hooks: trashHooks)
        trashViewModel.trash(trashItem)
        XCTAssertFalse(trashViewModel.canUndoLedgerAction)
    }

    func testLedgerUndoBannerExpiresAfterFiveSeconds() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 40_000)
        let item = AppViewModel.LedgerItem(title: "Archive me")
        let viewModel = AppViewModel(items: [item], now: { currentDate })

        viewModel.archive(item)
        let presentation = try XCTUnwrap(viewModel.pendingLedgerUndo)
        XCTAssertEqual(presentation.remaining(at: currentDate), 5, accuracy: 0.001)
        XCTAssertTrue(viewModel.canUndoLedgerAction)

        currentDate = currentDate.addingTimeInterval(4)
        viewModel.expirePendingLedgerUndoIfNeeded()
        XCTAssertTrue(viewModel.canUndoLedgerAction)

        currentDate = currentDate.addingTimeInterval(1)
        viewModel.expirePendingLedgerUndoIfNeeded()
        XCTAssertFalse(viewModel.canUndoLedgerAction)
        XCTAssertTrue(viewModel.items[0].isArchived)
    }

    func testLedgerUndoBannerPauseFreezesRemainingTime() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 50_000)
        let item = AppViewModel.LedgerItem(title: "Trash me")
        let viewModel = AppViewModel(items: [item], now: { currentDate })

        viewModel.trash(item)
        currentDate = currentDate.addingTimeInterval(2)
        viewModel.setLedgerUndoBannerPaused(true)

        XCTAssertTrue(try XCTUnwrap(viewModel.pendingLedgerUndo).isPaused)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.pendingLedgerUndo).remaining(at: currentDate),
            3,
            accuracy: 0.001
        )

        currentDate = currentDate.addingTimeInterval(10)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.pendingLedgerUndo).remaining(at: currentDate),
            3,
            accuracy: 0.001
        )

        viewModel.setLedgerUndoBannerPaused(false)
        let resumed = try XCTUnwrap(viewModel.pendingLedgerUndo)
        XCTAssertFalse(resumed.isPaused)
        XCTAssertEqual(resumed.expiresAt, currentDate.addingTimeInterval(3))
    }

    func testDismissingLedgerUndoBannerKeepsTheChange() {
        let item = AppViewModel.LedgerItem(title: "Keep archived")
        let viewModel = AppViewModel(items: [item])

        viewModel.archive(item)
        XCTAssertTrue(viewModel.items[0].isArchived)
        viewModel.dismissPendingLedgerUndo()

        XCTAssertFalse(viewModel.canUndoLedgerAction)
        XCTAssertTrue(viewModel.items[0].isArchived)
    }

    func testANewLedgerUndoResetsTheBannerDeadline() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 60_000)
        let first = AppViewModel.LedgerItem(title: "First")
        let second = AppViewModel.LedgerItem(title: "Second")
        let viewModel = AppViewModel(items: [first, second], now: { currentDate })

        viewModel.archive(first)
        currentDate = currentDate.addingTimeInterval(4)
        viewModel.trash(second)

        let presentation = try XCTUnwrap(viewModel.pendingLedgerUndo)
        XCTAssertEqual(viewModel.undoLedgerActionTitle, "Undo move to Trash")
        XCTAssertEqual(presentation.remaining(at: currentDate), 5, accuracy: 0.001)
        XCTAssertTrue(viewModel.items[0].isArchived)
        XCTAssertTrue(viewModel.items[1].isTrashed)
    }

    func testPausedLedgerUndoBannerDoesNotExpire() throws {
        var currentDate = Date(timeIntervalSinceReferenceDate: 70_000)
        let item = AppViewModel.LedgerItem(title: "Hold")
        let viewModel = AppViewModel(items: [item], now: { currentDate })

        viewModel.archive(item)
        currentDate = currentDate.addingTimeInterval(1)
        viewModel.setLedgerUndoBannerPaused(true)
        currentDate = currentDate.addingTimeInterval(10)
        viewModel.expirePendingLedgerUndoIfNeeded()

        XCTAssertTrue(viewModel.canUndoLedgerAction)
        XCTAssertTrue(viewModel.items[0].isArchived)
    }

    func testCaptureUndoFailureKeepsConfirmationAndErrorForRetry() {
        var hooks = AppViewModel.Hooks()
        hooks.onUndoCapture = { _ in "Could not move the capture to Trash." }
        let viewModel = AppViewModel(surfaceState: .confirmation, hooks: hooks)
        let item = AppViewModel.LedgerItem(title: "Captured")
        viewModel.showConfirmation(for: item)

        viewModel.undoConfirmation()

        XCTAssertNotNil(viewModel.confirmation)
        XCTAssertEqual(viewModel.surfaceState, .confirmation)
        XCTAssertEqual(viewModel.errorMessage, "Could not move the capture to Trash.")
        XCTAssertTrue(viewModel.confirmation?.isPaused == true)
    }

    func testPanelSeparatesReturnActivationFromSpaceCompletion() throws {
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        let space = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))

        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: returnKey), .activateSelection)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: space), .toggleCompletion)
    }

    func testPanelExposesEditAndContextMenuShortcuts() throws {
        let f2 = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 120
        ))
        let shiftF10 = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 109
        ))

        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: f2), .editSelection)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: shiftF10), .showActions)
    }

    func testSelectedRowContextMenuShortcutPostsOnlyForSelectedItem() {
        let item = AppViewModel.LedgerItem(title: "Actions")
        let viewModel = AppViewModel(items: [item])
        let expectation = expectation(description: "selected row actions notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .notchLedgerRowActionsRequested,
            object: nil,
            queue: .main
        ) { notification in
            guard (notification.object as? UUID) == item.id else { return }
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        viewModel.select(item)
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.showActions))
        wait(for: [expectation], timeout: 1)
    }
}
