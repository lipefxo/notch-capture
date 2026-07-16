import XCTest
@testable import NotchCapture

@MainActor
final class AppViewModelTests: XCTestCase {
    func testTagSearchUsesPlainTextAndAnyExactTag() {
        let lipe = AppViewModel.TagSummary(name: "Lipe")
        let work = AppViewModel.TagSummary(name: "Work")
        let ideas = AppViewModel.TagSummary(name: "Ideas")
        let lipeItem = AppViewModel.LedgerItem(title: "Launch plan", tags: [lipe])
        let workItem = AppViewModel.LedgerItem(title: "Launch checklist", tags: [work])
        let wrongText = AppViewModel.LedgerItem(title: "Dinner", tags: [lipe])
        let wrongTag = AppViewModel.LedgerItem(title: "Launch notes", tags: [ideas])
        let viewModel = AppViewModel(
            items: [lipeItem, workItem, wrongText, wrongTag],
            tags: [lipe, work, ideas]
        )

        viewModel.composerText = "launch @Lipe @Work"

        XCTAssertEqual(Set(viewModel.visibleItems.map(\.id)), Set([lipeItem.id, workItem.id]))
        XCTAssertTrue(viewModel.visibleFolders.isEmpty)

        viewModel.composerText = "Lipe"
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testInlineTagNamesDoNotLeakIntoPlainSearchButUnlinkedMentionsDo() {
        let home = AppViewModel.TagSummary(name: "Home")
        let tagged = AppViewModel.LedgerItem(
            title: "Buy supplies for @home",
            tags: [home]
        )
        let captured = AppViewModel.LedgerItem(title: "Copied message about @home")
        let viewModel = AppViewModel(items: [tagged, captured], tags: [home])

        viewModel.composerText = "home"
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [captured.id])

        viewModel.composerText = "@HOME"
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [tagged.id])
    }

    func testTagShelfCountsFollowFiltersAndKeepsStandaloneUnderAll() {
        let lipe = AppViewModel.TagSummary(name: "Lipe")
        let standalone = AppViewModel.TagSummary(name: "Standalone")
        let note = AppViewModel.LedgerItem(title: "Note", tags: [lipe])
        let task = AppViewModel.LedgerItem(kind: .task, title: "Task", tags: [lipe])
        let viewModel = AppViewModel(items: [note, task], tags: [standalone, lipe])

        XCTAssertEqual(viewModel.visibleTagGroups.map(\.name), ["Lipe", "Standalone"])
        XCTAssertEqual(viewModel.visibleTagGroups.map(\.count), [2, 0])

        viewModel.filter = .tasks
        XCTAssertEqual(viewModel.visibleTagGroups.map(\.name), ["Lipe"])
        XCTAssertEqual(viewModel.visibleTagGroups.map(\.count), [1])

        viewModel.composerText = "query"
        XCTAssertTrue(viewModel.visibleTagGroups.isEmpty)
    }

    func testTagAutocompleteConvertsSpaceAndCommitsWithTrailingSpace() {
        let product = AppViewModel.TagSummary(name: "Product-Launch")
        let viewModel = AppViewModel(tags: [product])
        viewModel.composerText = "Review @Product"

        XCTAssertEqual(viewModel.tagSuggestions.first?.name, "Product-Launch")

        viewModel.composerTextDidChange(from: "Review @Product", to: "Review @Product ")
        XCTAssertEqual(viewModel.composerText, "Review @Product-")

        viewModel.composerText = "Review @Prod"
        XCTAssertTrue(viewModel.acceptSelectedTagSuggestion())
        XCTAssertEqual(viewModel.composerText, "Review @Product-Launch ")
    }

    func testStandaloneTagSubmissionUsesTagHookInsteadOfItemCapture() {
        var createdTag: String?
        var capturedItem: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCreateTag = { createdTag = $0 }
        hooks.onCaptureText = { text, _ in capturedItem = text }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.composerText = "@Lipe"

        XCTAssertTrue(viewModel.canCreateStandaloneTag)
        viewModel.submitComposer()

        XCTAssertEqual(createdTag, "Lipe")
        XCTAssertNil(capturedItem)
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testReturnCreatesStandaloneTagWithoutAddingHyphens() {
        var createdTag: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCreateTag = { createdTag = $0 }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.composerText = "@work"

        viewModel.handleComposerReturn()
        XCTAssertEqual(createdTag, "work")
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testReturnWhitespaceFallbackCommitsTagThenCreatesItem() {
        let work = AppViewModel.TagSummary(name: "work")
        var captured: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in captured = text }
        let viewModel = AppViewModel(tags: [work], hooks: hooks)
        let activeTag = "Do this new thing at @work"
        viewModel.composerText = activeTag + " "

        viewModel.composerTextDidChange(
            from: activeTag,
            to: activeTag + " ",
            submittedByReturnKey: true
        )
        XCTAssertEqual(viewModel.composerText, activeTag + " ")
        XCTAssertNil(captured)

        viewModel.composerTextDidChange(
            from: activeTag + " ",
            to: activeTag + "  ",
            submittedByReturnKey: true
        )
        XCTAssertEqual(captured, activeTag)
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testEmbeddedNewTagIsNotPersistedUntilTheItemSubmits() {
        var createdStandaloneTag: String?
        var capturedItem: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCreateTag = { createdStandaloneTag = $0 }
        hooks.onCaptureText = { text, _ in capturedItem = text }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.composerText = "Plan the weekend for @home"

        viewModel.handleComposerReturn()

        XCTAssertEqual(viewModel.composerText, "Plan the weekend for @home ")
        XCTAssertNil(createdStandaloneTag)
        XCTAssertNil(capturedItem)

        viewModel.handleComposerReturn()

        XCTAssertEqual(capturedItem, "Plan the weekend for @home")
        XCTAssertNil(createdStandaloneTag)
        XCTAssertEqual(viewModel.composerText, "")
    }

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

    func testCreationTimestampSupportsTwentyFourHourFormat() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = 16
        components.minute = 59
        let date = try XCTUnwrap(components.date)

        let label = CaptureTimestampFormatter.string(
            from: date,
            timeFormat: .twentyFourHour,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )

        XCTAssertEqual(label, "Jul 15, 16:59")
    }

    func testTimeFormatChangeNotifiesPersistenceHook() {
        var persistedFormat: AppViewModel.TimeFormat?
        var hooks = AppViewModel.Hooks()
        hooks.onSetTimeFormat = { persistedFormat = $0 }
        let viewModel = AppViewModel(hooks: hooks)

        XCTAssertEqual(viewModel.timeFormat, .twelveHour)
        viewModel.timeFormat = .twentyFourHour

        XCTAssertEqual(persistedFormat, .twentyFourHour)
    }

    func testUnifiedInputFiltersMatchingItemsInsteadOfCapturing() {
        var captured: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in captured.append(text) }
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
        hooks.onCaptureText = { text, _ in captured.append(text) }
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

    func testRootShowsFoldersAndOnlyUnfiledItemsUntilSearching() {
        let work = AppViewModel.FolderSummary(name: "Work", sortOrder: 0)
        let ideas = AppViewModel.FolderSummary(name: "Ideas", sortOrder: 1)
        let inboxItem = AppViewModel.LedgerItem(title: "Loose thought", sortOrder: 0)
        let workTask = AppViewModel.LedgerItem(
            kind: .task,
            title: "Ship folder view",
            folderID: work.id,
            folderName: work.name,
            sortOrder: 0
        )
        let idea = AppViewModel.LedgerItem(
            title: "Try a compact row",
            folderID: ideas.id,
            folderName: ideas.name,
            sortOrder: 0
        )
        let viewModel = AppViewModel(items: [inboxItem, workTask, idea], folders: [work, ideas])

        XCTAssertEqual(viewModel.visibleFolders.map(\.id), [work.id, ideas.id])
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [inboxItem.id])
        XCTAssertEqual(viewModel.matchingItemCount(in: work.id), 1)

        viewModel.filter = .tasks

        XCTAssertEqual(viewModel.visibleFolders.map(\.id), [work.id])
        XCTAssertTrue(viewModel.visibleItems.isEmpty)

        viewModel.filter = .all
        viewModel.composerText = "compact"

        XCTAssertTrue(viewModel.visibleFolders.isEmpty)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [idea.id])
        XCTAssertTrue(viewModel.isShowingGlobalSearchResults)
    }

    func testFolderNameSearchShowsFolderAndIndependentItemMatches() {
        let projects = AppViewModel.FolderSummary(name: "Projects")
        let unrelatedFolderItem = AppViewModel.LedgerItem(
            title: "Unrelated capture",
            folderID: projects.id,
            folderName: projects.name
        )
        let matchingItem = AppViewModel.LedgerItem(title: "Projects launch notes")
        let viewModel = AppViewModel(
            items: [unrelatedFolderItem, matchingItem],
            folders: [projects]
        )

        viewModel.composerText = "projects"

        XCTAssertEqual(viewModel.visibleFolders.map(\.id), [projects.id])
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [matchingItem.id])
        XCTAssertEqual(viewModel.searchMatchCount, 2)
        XCTAssertTrue(viewModel.composerHasMatches)
        XCTAssertFalse(viewModel.canAddComposerText)

        viewModel.submitComposer()

        XCTAssertEqual(viewModel.browseLocation, .folder(projects.id))
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertNil(viewModel.selectedItemID)
    }

    func testFolderSearchResultsRespectEveryActiveFilter() {
        let populated = AppViewModel.FolderSummary(name: "Projects Active")
        let ineligible = AppViewModel.FolderSummary(name: "Projects Notes", sortOrder: 1)
        let now = Date.now
        let items = [
            AppViewModel.LedgerItem(
                kind: .task,
                title: "Open task",
                dueDate: now,
                folderID: populated.id,
                folderName: populated.name
            ),
            AppViewModel.LedgerItem(
                kind: .task,
                title: "Completed task",
                folderID: populated.id,
                folderName: populated.name,
                isCompleted: true,
                completedAt: now
            ),
            AppViewModel.LedgerItem(
                title: "Archived note",
                folderID: populated.id,
                folderName: populated.name,
                isArchived: true
            ),
            AppViewModel.LedgerItem(
                title: "Trashed note",
                folderID: populated.id,
                folderName: populated.name,
                isTrashed: true
            ),
            AppViewModel.LedgerItem(
                title: "Ordinary note",
                folderID: ineligible.id,
                folderName: ineligible.name
            ),
        ]
        let viewModel = AppViewModel(items: items, folders: [populated, ineligible])
        viewModel.composerText = "Projects"

        for filter in [
            AppViewModel.InboxFilter.tasks,
            .due,
            .completed,
            .archive,
            .trash,
        ] {
            viewModel.filter = filter
            XCTAssertEqual(viewModel.visibleFolders.map(\.id), [populated.id], "Filter: \(filter)")
        }
    }

    func testFolderBrowsingScopesSearchAndComposerDestination() {
        let work = AppViewModel.FolderSummary(name: "Work")
        let personal = AppViewModel.FolderSummary(name: "Personal", sortOrder: 1)
        let workItem = AppViewModel.LedgerItem(
            title: "Shared title",
            folderID: work.id,
            folderName: work.name
        )
        let personalItem = AppViewModel.LedgerItem(
            title: "Shared title",
            folderID: personal.id,
            folderName: personal.name
        )
        var capture: (text: String, folderID: UUID?)?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { capture = ($0, $1) }
        let viewModel = AppViewModel(
            items: [workItem, personalItem],
            folders: [work, personal],
            hooks: hooks
        )

        viewModel.openFolder(work)
        viewModel.composerText = "Shared"

        XCTAssertEqual(viewModel.navigationTitle, "Work")
        XCTAssertTrue(viewModel.visibleFolders.isEmpty)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [workItem.id])

        viewModel.composerText = "Write release notes"
        XCTAssertTrue(viewModel.canAddComposerText)
        viewModel.submitComposer()

        XCTAssertEqual(capture?.text, "Write release notes")
        XCTAssertEqual(capture?.folderID, work.id)
        XCTAssertEqual(viewModel.filter, .all)

        viewModel.openRoot()
        XCTAssertEqual(viewModel.browseLocation, .root)
        XCTAssertEqual(viewModel.navigationTitle, "Inbox")
    }

    func testMoveUsesFolderIdentityAndDeleteReturnsContentsToInbox() {
        let folder = AppViewModel.FolderSummary(name: "Research")
        let inbox = AppViewModel.LedgerItem(title: "Inbox", sortOrder: 0)
        let first = AppViewModel.LedgerItem(
            title: "First",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 0
        )
        let second = AppViewModel.LedgerItem(
            title: "Second",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 1
        )
        var moves: [(UUID, UUID?)] = []
        var deletedFolderID: UUID?
        var hooks = AppViewModel.Hooks()
        hooks.onMove = { moves.append(($0, $1)) }
        hooks.onDeleteFolder = { deletedFolderID = $0 }
        let viewModel = AppViewModel(items: [inbox, first, second], folders: [folder], hooks: hooks)

        viewModel.move(inbox, to: folder.id)

        XCTAssertEqual(moves.first?.0, inbox.id)
        XCTAssertEqual(moves.first?.1, folder.id)
        XCTAssertEqual(viewModel.items.first(where: { $0.id == inbox.id })?.folderID, folder.id)

        viewModel.deleteFolder(folder)

        XCTAssertEqual(deletedFolderID, folder.id)
        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertTrue(viewModel.items.allSatisfy { $0.folderID == nil && $0.folderName == nil })
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [inbox.id, first.id, second.id])
    }

    func testReorderIsScopedToTheOpenFolderAndDisabledForGlobalResults() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let first = AppViewModel.LedgerItem(
            title: "First",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 0
        )
        let second = AppViewModel.LedgerItem(
            title: "Second",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 1
        )
        let inbox = AppViewModel.LedgerItem(title: "Inbox", sortOrder: 0)
        var assignments: [ItemOrderAssignment] = []
        var hooks = AppViewModel.Hooks()
        hooks.onReorder = { assignments = $0 }
        let viewModel = AppViewModel(items: [first, second, inbox], folders: [folder], hooks: hooks)

        viewModel.openFolder(folder)
        XCTAssertTrue(
            viewModel.reorder(
                itemID: second.id,
                relativeTo: first.id,
                placement: .before,
                destinationPinned: false
            )
        )
        XCTAssertEqual(assignments.map(\.id), [second.id, first.id])
        XCTAssertEqual(viewModel.items.first(where: { $0.id == inbox.id })?.sortOrder, 0)

        viewModel.openRoot()
        viewModel.composerText = "Inbox"
        XCTAssertFalse(viewModel.canReorderVisibleItems)
        XCTAssertFalse(
            viewModel.reorder(
                itemID: inbox.id,
                relativeTo: nil,
                placement: .before,
                destinationPinned: true
            )
        )
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

@MainActor
final class LedgerReorderSessionTests: XCTestCase {
    func testDragResolverUsesRowMidpointsForReactivePlacement() {
        let item = AppViewModel.LedgerItem(title: "Target", sortOrder: 0)
        let regions: [LedgerDragRegion: CGRect] = [
            .feed: CGRect(x: 0, y: 0, width: 420, height: 500),
            .row(item.id): CGRect(x: 0, y: 100, width: 420, height: 60),
        ]

        let before = LedgerDragResolver.destination(
            at: CGPoint(x: 200, y: 115),
            regions: regions,
            items: [item],
            draggedItemID: UUID(),
            currentTarget: nil
        )
        let after = LedgerDragResolver.destination(
            at: CGPoint(x: 200, y: 145),
            regions: regions,
            items: [item],
            draggedItemID: UUID(),
            currentTarget: nil
        )

        XCTAssertEqual(before, .reorder(LedgerReorderTarget(
            targetID: item.id,
            placement: .before,
            destinationPinned: false
        )))
        XCTAssertEqual(after, .reorder(LedgerReorderTarget(
            targetID: item.id,
            placement: .after,
            destinationPinned: false
        )))
    }

    func testDragResolverPrioritizesFolderAndRetainsTargetOverPlaceholder() {
        let draggedID = UUID()
        let folderID = UUID()
        let currentTarget = LedgerReorderTarget(
            targetID: UUID(),
            placement: .after,
            destinationPinned: false
        )
        let regions: [LedgerDragRegion: CGRect] = [
            .feed: CGRect(x: 0, y: 0, width: 420, height: 500),
            .folder(folderID): CGRect(x: 0, y: 0, width: 420, height: 50),
            .row(draggedID): CGRect(x: 0, y: 100, width: 420, height: 60),
        ]

        XCTAssertEqual(
            LedgerDragResolver.destination(
                at: CGPoint(x: 200, y: 25),
                regions: regions,
                items: [],
                draggedItemID: draggedID,
                currentTarget: currentTarget
            ),
            .folder(folderID)
        )
        XCTAssertEqual(
            LedgerDragResolver.destination(
                at: CGPoint(x: 200, y: 130),
                regions: regions,
                items: [],
                draggedItemID: draggedID,
                currentTarget: currentTarget
            ),
            .reorder(currentTarget)
        )
    }

    func testDragResolverCancelsOutsideTheFeed() {
        XCTAssertNil(LedgerDragResolver.destination(
            at: CGPoint(x: 200, y: 520),
            regions: [.feed: CGRect(x: 0, y: 0, width: 420, height: 500)],
            items: [],
            draggedItemID: UUID(),
            currentTarget: LedgerReorderTarget(
                targetID: UUID(),
                placement: .before,
                destinationPinned: false
            )
        ))
    }

    func testPreviewReordersRowsWithoutMutatingOrPersistingTheViewModel() {
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let second = AppViewModel.LedgerItem(title: "Second", sortOrder: 1)
        let third = AppViewModel.LedgerItem(title: "Third", sortOrder: 2)
        var persistenceCalls = 0
        var hooks = AppViewModel.Hooks()
        hooks.onReorder = { _ in persistenceCalls += 1 }
        let viewModel = AppViewModel(items: [first, second, third], hooks: hooks)
        let session = LedgerReorderSession(
            draggedItemID: third.id,
            reorderTarget: LedgerReorderTarget(
                targetID: first.id,
                placement: .before,
                destinationPinned: false
            )
        )

        let preview = session.previewing(viewModel.visibleItems)

        XCTAssertEqual(preview.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(persistenceCalls, 0)
    }

    func testPreviewMovesRowsAcrossPinnedGroupsAndIntoAnEmptyGroup() {
        let pinned = AppViewModel.LedgerItem(title: "Pinned", isPinned: true, sortOrder: 0)
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let second = AppViewModel.LedgerItem(title: "Second", sortOrder: 1)
        let pinAtTop = LedgerReorderSession(
            draggedItemID: second.id,
            reorderTarget: LedgerReorderTarget(
                targetID: nil,
                placement: .before,
                destinationPinned: true
            )
        )

        let pinnedPreview = pinAtTop.previewing([pinned, first, second])

        XCTAssertEqual(pinnedPreview.map(\.id), [second.id, pinned.id, first.id])
        XCTAssertTrue(pinnedPreview[0].isPinned)

        let onlyUnpinned = LedgerReorderSession(
            draggedItemID: first.id,
            reorderTarget: LedgerReorderTarget(
                targetID: nil,
                placement: .before,
                destinationPinned: true
            )
        ).previewing([first, second])

        XCTAssertEqual(onlyUnpinned.map(\.id), [first.id, second.id])
        XCTAssertTrue(onlyUnpinned[0].isPinned)
    }

    func testFolderHoverAndCancellationRestoreTheOriginalPresentation() {
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let second = AppViewModel.LedgerItem(title: "Second", sortOrder: 1)
        let target = LedgerReorderTarget(
            targetID: first.id,
            placement: .before,
            destinationPinned: false
        )

        let folderHover = LedgerReorderSession(
            draggedItemID: second.id,
            reorderTarget: target,
            targetedFolderID: UUID()
        )
        let cancelled = LedgerReorderSession(draggedItemID: second.id)

        XCTAssertEqual(folderHover.previewing([first, second]).map(\.id), [first.id, second.id])
        XCTAssertEqual(cancelled.previewing([first, second]).map(\.id), [first.id, second.id])
    }

    func testOpenFolderPreviewIsScopedToItsVisibleItems() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let first = AppViewModel.LedgerItem(
            title: "First",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 0
        )
        let second = AppViewModel.LedgerItem(
            title: "Second",
            folderID: folder.id,
            folderName: folder.name,
            sortOrder: 1
        )
        let inbox = AppViewModel.LedgerItem(title: "Inbox", sortOrder: 0)
        let viewModel = AppViewModel(items: [first, second, inbox], folders: [folder])
        viewModel.openFolder(folder)
        let session = LedgerReorderSession(
            draggedItemID: second.id,
            reorderTarget: LedgerReorderTarget(
                targetID: first.id,
                placement: .before,
                destinationPinned: false
            )
        )

        let preview = session.previewing(viewModel.visibleItems)

        XCTAssertEqual(preview.map(\.id), [second.id, first.id])
        XCTAssertEqual(viewModel.items.first(where: { $0.id == inbox.id })?.sortOrder, 0)
    }

    func testMovingPinnedItemIntoFolderPreservesPinAndPlacesItAtTop() {
        let folder = AppViewModel.FolderSummary(name: "Work")
        let existing = AppViewModel.LedgerItem(
            title: "Existing",
            folderID: folder.id,
            folderName: folder.name,
            isPinned: true,
            sortOrder: 4
        )
        let moving = AppViewModel.LedgerItem(title: "Moving", isPinned: true, sortOrder: 2)
        var moves: [(UUID, UUID?)] = []
        var hooks = AppViewModel.Hooks()
        hooks.onMove = { moves.append(($0, $1)) }
        let viewModel = AppViewModel(items: [existing, moving], folders: [folder], hooks: hooks)

        viewModel.move(moving, to: folder.id)

        let moved = viewModel.items.first(where: { $0.id == moving.id })
        XCTAssertTrue(moved?.isPinned == true)
        XCTAssertEqual(moved?.folderID, folder.id)
        XCTAssertEqual(moved?.sortOrder, 3)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.0, moving.id)
        XCTAssertEqual(moves.first?.1, folder.id)
    }
}
