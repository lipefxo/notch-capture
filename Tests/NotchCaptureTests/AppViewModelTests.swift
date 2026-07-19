import XCTest
import UniformTypeIdentifiers
@testable import NotchCapture

@MainActor
final class AppViewModelTests: XCTestCase {
    func testImagePasteRoutesOnlyImageProvidersToTheComposerHook() {
        let imageProvider = NSItemProvider()
        imageProvider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(Data("pixels".utf8), nil)
            return nil
        }
        let fileURLProvider = NSItemProvider(
            item: URL(fileURLWithPath: "/tmp/CleanShot.png") as NSURL,
            typeIdentifier: UTType.fileURL.identifier
        )
        let textProvider = NSItemProvider(object: "plain text" as NSString)
        var acceptedProviders: [NSItemProvider] = []
        var hooks = AppViewModel.Hooks()
        hooks.onPastedImageProviders = { providers, _ in acceptedProviders = providers }
        let viewModel = AppViewModel(hooks: hooks)

        XCTAssertTrue(viewModel.acceptPastedImages([textProvider, imageProvider, fileURLProvider]))
        XCTAssertEqual(acceptedProviders.count, 2)
        XCTAssertTrue(acceptedProviders[0] === imageProvider)
        XCTAssertTrue(acceptedProviders[1] === fileURLProvider)
        XCTAssertFalse(viewModel.acceptPastedImages([textProvider]))
    }

    func testCompletedPasteDoesNotRepopulateADiscardedDraft() throws {
        let imageProvider = NSItemProvider()
        imageProvider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(Data("pixels".utf8), nil)
            return nil
        }
        var pasteDraftID: UUID?
        var hooks = AppViewModel.Hooks()
        hooks.onPastedImageProviders = { _, draftID in pasteDraftID = draftID }
        let viewModel = AppViewModel(surfaceState: .expanded, hooks: hooks)

        XCTAssertTrue(viewModel.acceptPastedImages([imageProvider]))
        viewModel.dismiss()
        viewModel.appendComposerImages(
            [composerImage(name: "Late.png", contents: "late")],
            toComposerDraft: try XCTUnwrap(pasteDraftID)
        )

        XCTAssertTrue(viewModel.composerImages.isEmpty)
    }

    func testImageFileURLClipboardRepresentationLoadsAsComposerImage() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let imageURL = root.appendingPathComponent("Design/reference-thumbnail.png")

        let image = try XCTUnwrap(AppCoordinator.loadPastedImageFile(at: imageURL, index: 1))

        XCTAssertEqual(image.filename, "reference-thumbnail.png")
        XCTAssertEqual(image.typeIdentifier, UTType.png.identifier)
        XCTAssertEqual(image.data, try Data(contentsOf: imageURL))
        XCTAssertNil(AppCoordinator.loadPastedImageFile(
            at: root.appendingPathComponent("Package.swift"),
            index: 2
        ))
    }

    func testCleanShotPasteboardItemPrefersBitmapDataOverItsFileURLText() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let imageURL = root.appendingPathComponent("Design/reference-thumbnail.png")
        let imageData = try Data(contentsOf: imageURL)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchCaptureTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(imageURL.absoluteString, forType: .fileURL)
        item.setData(imageData, forType: .png)
        pasteboard.writeObjects([item])

        let images = AppCoordinator.composerImages(from: pasteboard)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].filename, "reference-thumbnail.png")
        XCTAssertEqual(images[0].typeIdentifier, UTType.png.identifier)
        XCTAssertEqual(images[0].data, imageData)
    }

    func testComposerImagesAppendInOrderAndCanBeRemovedIndividually() {
        let first = composerImage(name: "First.png", contents: "first")
        let second = composerImage(name: "Second.png", contents: "second")
        let third = composerImage(name: "Third.png", contents: "third")
        let viewModel = AppViewModel()

        viewModel.appendComposerImages([first, second])
        viewModel.appendComposerImages([third])

        XCTAssertEqual(viewModel.composerImages.map(\.id), [first.id, second.id, third.id])
        XCTAssertTrue(viewModel.composerHasDraft)
        XCTAssertTrue(viewModel.canSubmitComposer)

        viewModel.removeComposerImage(id: second.id)
        XCTAssertEqual(viewModel.composerImages.map(\.id), [first.id, third.id])
    }

    func testComposerImagesSubmitAsOneFolderScopedCaptureEvenWhenTextMatches() {
        let folder = AppViewModel.FolderSummary(name: "Projects")
        let work = AppViewModel.TagSummary(name: "Work")
        let matchingItem = AppViewModel.LedgerItem(
            title: "Review launch",
            folderID: folder.id,
            tags: [work]
        )
        let images = [
            composerImage(name: "First.png", contents: "first"),
            composerImage(name: "Second.jpg", contents: "second", type: .jpeg),
        ]
        var capturedText: String?
        var capturedImages: [AppViewModel.ComposerImage] = []
        var capturedFolderID: UUID?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureComposerImages = { text, images, folderID in
            capturedText = text
            capturedImages = images
            capturedFolderID = folderID
            return nil
        }
        let viewModel = AppViewModel(
            items: [matchingItem],
            folders: [folder],
            tags: [work],
            hooks: hooks
        )
        viewModel.openFolder(folder)
        viewModel.composerText = "Review @Work"
        viewModel.appendComposerImages(images)

        XCTAssertTrue(viewModel.composerHasMatches)
        XCTAssertFalse(viewModel.canAddComposerText)
        XCTAssertTrue(viewModel.canSubmitComposer)

        viewModel.submitComposer()

        XCTAssertEqual(capturedText, "Review @Work")
        XCTAssertEqual(capturedImages, images)
        XCTAssertEqual(capturedFolderID, folder.id)
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertTrue(viewModel.composerImages.isEmpty)
    }

    func testImageOnlyAndTagOnlyDraftsSubmitAsCaptures() {
        let image = composerImage(name: "Capture.png", contents: "pixels")
        var submissions: [(String, [AppViewModel.ComposerImage])] = []
        var createdTag: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureComposerImages = { text, images, _ in
            submissions.append((text, images))
            return nil
        }
        hooks.onCreateTag = { createdTag = $0 }
        let viewModel = AppViewModel(hooks: hooks)

        viewModel.appendComposerImages([image])
        viewModel.submitComposer()
        XCTAssertEqual(submissions.first?.0, "")
        XCTAssertEqual(submissions.first?.1, [image])

        viewModel.composerText = "@Ideas"
        viewModel.appendComposerImages([image])
        XCTAssertFalse(viewModel.canCreateStandaloneTag)
        viewModel.submitComposer()

        XCTAssertEqual(submissions.last?.0, "@Ideas")
        XCTAssertNil(createdTag)
    }

    func testFailedImageSubmissionPreservesTheCompleteDraft() {
        let image = composerImage(name: "Capture.png", contents: "pixels")
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureComposerImages = { _, _, _ in "Could not save pasted images." }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.composerText = "Keep this @Work"
        viewModel.appendComposerImages([image])

        viewModel.submitComposer()

        XCTAssertEqual(viewModel.composerText, "Keep this @Work")
        XCTAssertEqual(viewModel.composerImages, [image])
        XCTAssertEqual(viewModel.errorMessage, "Could not save pasted images.")
    }

    func testComposerImageDraftClearsOnEscapeNavigationAndDismissal() {
        let image = composerImage(name: "Capture.png", contents: "pixels")
        let folder = AppViewModel.FolderSummary(name: "Projects")
        let viewModel = AppViewModel(surfaceState: .expanded, folders: [folder])
        viewModel.composerText = "Draft"
        viewModel.appendComposerImages([image])

        viewModel.handleDismissalRequest(.escape)
        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertTrue(viewModel.composerImages.isEmpty)

        viewModel.appendComposerImages([image])
        viewModel.openFolder(folder)
        XCTAssertTrue(viewModel.composerImages.isEmpty)

        viewModel.appendComposerImages([image])
        viewModel.dismiss()
        XCTAssertTrue(viewModel.composerImages.isEmpty)
        XCTAssertNotEqual(viewModel.surfaceState, .expanded)
    }

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

    func testTagAutocompleteUsesSpaceAsDelimiterAndCommitsWithTrailingSpace() {
        let product = AppViewModel.TagSummary(name: "Product-Launch")
        let viewModel = AppViewModel(tags: [product])
        viewModel.composerText = "Review @Product"

        XCTAssertEqual(viewModel.tagSuggestions.first?.name, "Product-Launch")

        viewModel.composerText = "Review @Product "
        viewModel.composerTextDidChange(from: "Review @Product", to: "Review @Product ")
        XCTAssertEqual(viewModel.composerText, "Review @Product ")
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)

        viewModel.composerText = "Review @Prod"
        let textBeforeAcceptingSuggestion = viewModel.composerText
        XCTAssertTrue(viewModel.acceptSelectedTagSuggestion())
        viewModel.composerTextDidChange(
            from: textBeforeAcceptingSuggestion,
            to: viewModel.composerText
        )
        XCTAssertEqual(viewModel.composerText, "Review @Product-Launch ")
    }

    func testTrailingTagCanBeDelimitedAndSubmittedWithTheItem() {
        let bags = AppViewModel.TagSummary(name: "bags")
        var capturedItem: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in capturedItem = text }
        let viewModel = AppViewModel(tags: [bags], hooks: hooks)
        let activeTag = "do this and that and that @bags"

        viewModel.composerText = activeTag + " "
        viewModel.composerTextDidChange(from: activeTag, to: activeTag + " ")
        viewModel.submitComposer()

        XCTAssertEqual(capturedItem, activeTag)
        XCTAssertEqual(CaptureTagParser.parse(capturedItem ?? "").tagNames, ["bags"])
        XCTAssertEqual(viewModel.composerText, "")
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
        var capturedItem: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCreateTag = { createdTag = $0 }
        hooks.onCaptureText = { text, _ in capturedItem = text }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.composerText = "@work"

        viewModel.handleComposerReturn()
        XCTAssertEqual(createdTag, "work")
        XCTAssertNil(capturedItem)
        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
    }

    func testReturnCommitsExistingTagThenCreatesItem() {
        let work = AppViewModel.TagSummary(name: "work")
        var captured: String?
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in captured = text }
        let viewModel = AppViewModel(tags: [work], hooks: hooks)
        let activeTag = "Do this new thing at @work"
        viewModel.composerText = activeTag

        viewModel.handleComposerReturn()
        XCTAssertEqual(viewModel.composerText, activeTag + " ")
        XCTAssertNil(captured)

        viewModel.handleComposerReturn()
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

    func testCommandReturnCapturesEvenWhenItemsMatch() {
        var captured: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCaptureText = { text, _ in captured.append(text) }
        let matchingItem = AppViewModel.LedgerItem(title: "Book studio time")
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [matchingItem],
            hooks: hooks
        )

        viewModel.composerText = "studio"
        XCTAssertTrue(viewModel.composerHasMatches)

        viewModel.submitComposer(capturingAnyway: true)

        XCTAssertEqual(captured, ["studio"])
        XCTAssertEqual(viewModel.composerText, "")
    }

    func testArrowKeysNavigateTheVisibleLedgerAndReturnToComposer() {
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [
                AppViewModel.LedgerItem(title: "First"),
                AppViewModel.LedgerItem(title: "Second"),
            ]
        )
        let rows = viewModel.pinnedItems + viewModel.unpinnedItems
        XCTAssertEqual(rows.count, 2)

        XCTAssertFalse(viewModel.moveLedgerSelection(by: -1))
        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedItemID, rows[0].id)
        XCTAssertEqual(viewModel.keyboardFocus, .selectedRow)

        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedItemID, rows[1].id)

        // Past the last row the selection stays put.
        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedItemID, rows[1].id)

        XCTAssertTrue(viewModel.moveLedgerSelection(by: -1))
        XCTAssertEqual(viewModel.selectedItemID, rows[0].id)

        // Above the first row focus returns to the composer.
        XCTAssertTrue(viewModel.moveLedgerSelection(by: -1))
        XCTAssertNil(viewModel.selectedItemID)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
    }

    func testArrowKeysWalkFoldersBeforeItemsAndReturnOpensTheSelectedFolder() {
        let folder = AppViewModel.FolderSummary(name: "Bags", sortOrder: 0)
        let item = AppViewModel.LedgerItem(title: "Loose thought")
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [item],
            folders: [folder]
        )

        // Folders render above items, so ↓ selects the folder first.
        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedFolderID, folder.id)
        XCTAssertNil(viewModel.selectedItemID)

        XCTAssertTrue(viewModel.moveLedgerSelection(by: 1))
        XCTAssertEqual(viewModel.selectedItemID, item.id)
        XCTAssertNil(viewModel.selectedFolderID)

        XCTAssertTrue(viewModel.moveLedgerSelection(by: -1))
        XCTAssertEqual(viewModel.selectedFolderID, folder.id)

        // Return (toggleCompletion key command) opens the selected folder.
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertEqual(viewModel.browseLocation, .folder(folder.id))
        XCTAssertNil(viewModel.selectedFolderID)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
    }

    func testDeleteKeyOnSelectedFolderIsSwallowedWithoutMutation() {
        let folder = AppViewModel.FolderSummary(name: "Bags", sortOrder: 0)
        var trashed: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onTrash = { trashed.append($0) }
        let viewModel = AppViewModel(surfaceState: .expanded, folders: [folder], hooks: hooks)

        viewModel.moveLedgerSelection(by: 1)
        XCTAssertEqual(viewModel.selectedFolderID, folder.id)

        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.moveToTrash))
        XCTAssertTrue(trashed.isEmpty)
        XCTAssertEqual(viewModel.selectedFolderID, folder.id)
    }

    func testPinnedItemsComeFirstInKeyboardNavigationOrder() {
        let pinned = AppViewModel.LedgerItem(title: "Pinned", isPinned: true)
        let plain = AppViewModel.LedgerItem(title: "Plain")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [plain, pinned])

        viewModel.moveLedgerSelection(by: 1)

        XCTAssertEqual(viewModel.selectedItemID, pinned.id)
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
        XCTAssertEqual(viewModel.navigationTitle, "Capture")
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
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
    }

    func testKeyboardDeleteSelectsTheRowThatReplacesTheRemovedRow() {
        let first = AppViewModel.LedgerItem(title: "First", sortOrder: 0)
        let middle = AppViewModel.LedgerItem(title: "Middle", sortOrder: 1)
        let last = AppViewModel.LedgerItem(title: "Last", sortOrder: 2)
        let viewModel = AppViewModel(surfaceState: .expanded, items: [first, middle, last])

        viewModel.select(middle)

        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.moveToTrash))
        XCTAssertEqual(viewModel.selectedItemID, last.id)
        XCTAssertEqual(viewModel.keyboardFocus, .selectedRow)

        // Deleting the final visible row falls back to its predecessor.
        XCTAssertTrue(viewModel.performSelectedRowKeyboardCommand(.moveToTrash))
        XCTAssertEqual(viewModel.selectedItemID, first.id)
        XCTAssertEqual(viewModel.keyboardFocus, .selectedRow)
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

    func testInlineEditingSavesExactTextAndSuppressesRowCommandsAndReordering() {
        let home = AppViewModel.TagSummary(name: "Home")
        let item = AppViewModel.LedgerItem(
            title: "Original",
            text: "Original @Home",
            tags: [home]
        )
        var persisted: (UUID, String)?
        var completionToggleCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onUpdateText = { id, text in
            persisted = (id, text)
            return nil
        }
        hooks.onToggleComplete = { _ in completionToggleCount += 1 }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [item],
            tags: [home],
            hooks: hooks
        )

        viewModel.beginEditing(item)

        XCTAssertEqual(viewModel.itemEditSession?.originalText, "Original @Home")
        XCTAssertEqual(viewModel.itemEditSession?.draft, "Original @Home")
        XCTAssertEqual(viewModel.keyboardFocus, .itemEditor)
        XCTAssertEqual(viewModel.selectedItemID, item.id)
        XCTAssertFalse(viewModel.canReorderVisibleItems)
        XCTAssertFalse(viewModel.performSelectedRowKeyboardCommand(.toggleCompletion))
        XCTAssertFalse(viewModel.items[0].isCompleted)
        XCTAssertEqual(completionToggleCount, 0)

        let edited = "First line\n\nSecond line @Home"
        viewModel.updateEditingDraft(edited)
        XCTAssertTrue(viewModel.saveEditing())

        XCTAssertEqual(persisted?.0, item.id)
        XCTAssertEqual(persisted?.1, edited)
        XCTAssertNil(viewModel.itemEditSession)
        XCTAssertEqual(viewModel.keyboardFocus, .selectedRow)
        XCTAssertEqual(viewModel.items[0].text, edited)
        XCTAssertEqual(viewModel.items[0].title, "First line")
        XCTAssertEqual(viewModel.items[0].detail, "Second line @Home")
        XCTAssertEqual(viewModel.items[0].tags, [home])
    }

    func testBeginningAndEndingEditingPreservesVisibleRowsAndCompletionState() {
        let now = Date.now
        let first = AppViewModel.LedgerItem(
            title: "First",
            createdAt: now.addingTimeInterval(-120),
            sortOrder: 0
        )
        let target = AppViewModel.LedgerItem(
            title: "Edit me",
            createdAt: now.addingTimeInterval(-60),
            sortOrder: 1
        )
        let completed = AppViewModel.LedgerItem(
            kind: .task,
            title: "Already completed",
            createdAt: now.addingTimeInterval(-180),
            isCompleted: true,
            completedAt: now.addingTimeInterval(-30),
            sortOrder: 2
        )
        var completedIDs: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onToggleComplete = { completedIDs.append($0) }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [first, target, completed],
            hooks: hooks
        )
        let visibleIDs = viewModel.visibleItems.map(\.id)
        let completionStates = Dictionary(
            uniqueKeysWithValues: viewModel.items.map { ($0.id, $0.isCompleted) }
        )

        viewModel.beginEditing(target)

        XCTAssertFalse(viewModel.canReorderVisibleItems)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), visibleIDs)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: viewModel.items.map { ($0.id, $0.isCompleted) }),
            completionStates
        )
        XCTAssertTrue(completedIDs.isEmpty)

        viewModel.cancelEditing()

        XCTAssertTrue(viewModel.canReorderVisibleItems)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), visibleIDs)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: viewModel.items.map { ($0.id, $0.isCompleted) }),
            completionStates
        )
        XCTAssertTrue(completedIDs.isEmpty)
    }

    func testInlineEditingCancelAndFailuresKeepStoredContentSafe() {
        let item = AppViewModel.LedgerItem(title: "Original")
        var persistedTexts: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onUpdateText = { _, text in
            persistedTexts.append(text)
            return text == "Rejected" ? "Could not save." : nil
        }
        let viewModel = AppViewModel(surfaceState: .expanded, items: [item], hooks: hooks)

        viewModel.beginEditing(item)
        viewModel.updateEditingDraft("Changed")
        viewModel.cancelEditing()
        XCTAssertEqual(viewModel.items[0].text, "Original")
        XCTAssertTrue(persistedTexts.isEmpty)

        viewModel.beginEditing(item)
        viewModel.updateEditingDraft(" \n ")
        XCTAssertFalse(viewModel.saveEditing())
        XCTAssertNotNil(viewModel.itemEditSession)
        XCTAssertEqual(viewModel.keyboardFocus, .itemEditor)
        XCTAssertTrue(persistedTexts.isEmpty)

        viewModel.updateEditingDraft("Rejected")
        XCTAssertFalse(viewModel.saveEditing())
        XCTAssertEqual(viewModel.errorMessage, "Could not save.")
        XCTAssertEqual(viewModel.itemEditSession?.draft, "Rejected")
        XCTAssertEqual(viewModel.items[0].text, "Original")
    }

    func testDismissalRequestsCancelOnEscapeAndSaveOnExternalClick() {
        let item = AppViewModel.LedgerItem(title: "Original")
        var persistedTexts: [String] = []
        var hooks = AppViewModel.Hooks()
        hooks.onUpdateText = { _, text in
            persistedTexts.append(text)
            return nil
        }
        let viewModel = AppViewModel(surfaceState: .expanded, items: [item], hooks: hooks)

        viewModel.beginEditing(item)
        viewModel.updateEditingDraft("Cancelled")
        viewModel.handleDismissalRequest(.escape)
        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertNil(viewModel.itemEditSession)
        XCTAssertTrue(persistedTexts.isEmpty)

        viewModel.beginEditing(item)
        viewModel.updateEditingDraft("Saved outside")
        viewModel.handleDismissalRequest(.externalClick)
        XCTAssertEqual(persistedTexts, ["Saved outside"])
        XCTAssertNil(viewModel.itemEditSession)
        XCTAssertNotEqual(viewModel.surfaceState, .expanded)

        hooks.onUpdateText = { _, _ in "Could not save." }
        let failingViewModel = AppViewModel(surfaceState: .expanded, items: [item], hooks: hooks)
        failingViewModel.beginEditing(item)
        failingViewModel.updateEditingDraft("Unsaved outside")
        failingViewModel.handleDismissalRequest(.externalClick)
        XCTAssertEqual(failingViewModel.surfaceState, .expanded)
        XCTAssertEqual(failingViewModel.itemEditSession?.draft, "Unsaved outside")
        XCTAssertEqual(failingViewModel.errorMessage, "Could not save.")
    }

    func testEscapeClearsClickedTagFilterBeforeDismissing() {
        let home = AppViewModel.TagSummary(name: "Home")
        let tagged = AppViewModel.LedgerItem(title: "Tagged", tags: [home])
        let untagged = AppViewModel.LedgerItem(title: "Untagged")
        var dismissalCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { dismissalCount += 1 }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [tagged, untagged],
            tags: [home],
            hooks: hooks
        )

        viewModel.search(for: home)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [tagged.id])

        viewModel.handleDismissalRequest(.escape)

        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(Set(viewModel.visibleItems.map(\.id)), Set([tagged.id, untagged.id]))
        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
        XCTAssertEqual(dismissalCount, 0)

        viewModel.handleDismissalRequest(.escape)

        XCTAssertNotEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(dismissalCount, 1)
    }

    func testEscapeClearsPlainTextSearchBeforeDismissing() {
        var dismissalCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { dismissalCount += 1 }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            items: [
                AppViewModel.LedgerItem(title: "Launch plan"),
                AppViewModel.LedgerItem(title: "Dinner")
            ],
            hooks: hooks
        )
        viewModel.composerText = "launch"
        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["Launch plan"])

        viewModel.handleDismissalRequest(.escape)

        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(Set(viewModel.visibleItems.map(\.title)), Set(["Launch plan", "Dinner"]))
        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
        XCTAssertEqual(dismissalCount, 0)
    }

    func testEscapeDismissesAutocompleteBeforeClearingItsQuery() {
        let work = AppViewModel.TagSummary(name: "Work")
        let viewModel = AppViewModel(surfaceState: .expanded, tags: [work])
        viewModel.composerText = "@wo"
        XCTAssertFalse(viewModel.tagSuggestions.isEmpty)

        viewModel.handleDismissalRequest(.escape)

        XCTAssertEqual(viewModel.composerText, "@wo")
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertEqual(viewModel.surfaceState, .expanded)

        viewModel.handleDismissalRequest(.escape)

        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertEqual(viewModel.surfaceState, .expanded)
    }

    func testEscapeReturnsFromFolderBeforeDismissing() {
        let folder = AppViewModel.FolderSummary(name: "Projects")
        var dismissalCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { dismissalCount += 1 }
        let viewModel = AppViewModel(
            surfaceState: .expanded,
            folders: [folder],
            hooks: hooks
        )
        viewModel.openFolder(folder)

        viewModel.handleDismissalRequest(.escape)

        XCTAssertTrue(viewModel.isAtRoot)
        XCTAssertEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(viewModel.keyboardFocus, .composer)
        XCTAssertEqual(dismissalCount, 0)
    }

    func testExternalClickDismissesWithAnActiveQuery() {
        var dismissalCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onDismiss = { dismissalCount += 1 }
        let viewModel = AppViewModel(surfaceState: .expanded, hooks: hooks)
        viewModel.composerText = "launch"

        viewModel.handleDismissalRequest(.externalClick)

        XCTAssertEqual(viewModel.composerText, "")
        XCTAssertNotEqual(viewModel.surfaceState, .expanded)
        XCTAssertEqual(dismissalCount, 1)
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

    func testCompletingOnTasksFilterHoldsTheRowUntilReleased() {
        var completedIDs: [UUID] = []
        var hooks = AppViewModel.Hooks()
        hooks.onToggleComplete = { completedIDs.append($0) }
        let task = AppViewModel.LedgerItem(kind: .task, title: "Ship it")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [task], hooks: hooks)
        viewModel.filter = .tasks

        viewModel.toggleComplete(task)

        XCTAssertTrue(viewModel.items[0].isCompleted)
        XCTAssertEqual(completedIDs, [task.id])
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])

        viewModel.filter = .completed
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])
        viewModel.filter = .tasks

        viewModel.releaseCompletionHold(task.id)

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testUncompletingDuringTheHoldCancelsItAndKeepsTheRow() {
        let task = AppViewModel.LedgerItem(kind: .task, title: "Maybe not")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [task])
        viewModel.filter = .tasks

        viewModel.toggleComplete(task)
        viewModel.toggleComplete(viewModel.items[0])

        XCTAssertFalse(viewModel.items[0].isCompleted)
        XCTAssertNil(viewModel.items[0].completedAt)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])

        // A stale release must not touch the reopened row.
        viewModel.releaseCompletionHold(task.id)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])
    }

    func testCompletingOnAllKeepsSortPositionUntilTheHoldReleases() {
        let now = Date.now
        let older = AppViewModel.LedgerItem(
            kind: .task,
            title: "Older",
            createdAt: now.addingTimeInterval(-120)
        )
        let newer = AppViewModel.LedgerItem(
            title: "Newer",
            createdAt: now.addingTimeInterval(-60)
        )
        let viewModel = AppViewModel(surfaceState: .expanded, items: [older, newer])

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [newer.id, older.id])

        viewModel.toggleComplete(older)

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [newer.id, older.id])

        viewModel.releaseCompletionHold(older.id)

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [older.id, newer.id])
    }

    func testTrashingAHeldItemRemovesItImmediately() {
        let task = AppViewModel.LedgerItem(kind: .task, title: "Complete then trash")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [task])
        viewModel.filter = .tasks

        viewModel.toggleComplete(task)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])

        viewModel.trash(viewModel.items[0])

        XCTAssertTrue(viewModel.items[0].isTrashed)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
        XCTAssertTrue(viewModel.completionHoldIDs.isEmpty)
    }

    func testDismissFlushesCompletionHolds() {
        let task = AppViewModel.LedgerItem(kind: .task, title: "Done and gone")
        let viewModel = AppViewModel(surfaceState: .expanded, items: [task])
        viewModel.filter = .tasks

        viewModel.toggleComplete(task)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [task.id])

        viewModel.dismiss()

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    func testOnlyAttachmentItemsDisplayAPrefixIcon() {
        let textNote = AppViewModel.LedgerItem(title: "Text note")
        let textTask = AppViewModel.LedgerItem(kind: .task, title: "Text task")
        let fileAttachment = AppViewModel.LedgerItem(
            title: "Reference",
            attachments: [.init(kind: .file, name: "brief.pdf")]
        )
        let imageAttachment = AppViewModel.LedgerItem(
            title: "Reference image",
            attachments: [.init(kind: .image, name: "reference.png")]
        )
        let linkOnly = AppViewModel.LedgerItem(
            title: "www.youtube.com",
            text: "",
            attachments: [.init(kind: .link, name: "www.youtube.com")]
        )

        XCTAssertFalse(textNote.displaysAttachmentPrefix)
        XCTAssertFalse(textTask.displaysAttachmentPrefix)
        XCTAssertTrue(fileAttachment.displaysAttachmentPrefix)
        XCTAssertFalse(imageAttachment.displaysAttachmentPrefix)
        XCTAssertFalse(linkOnly.displaysAttachmentPrefix)
    }

    func testImageAttachmentsPreserveTheirLedgerOrderAndIncludeScreenshots() {
        let file = AppViewModel.LedgerAttachment(kind: .file, name: "brief.pdf")
        let first = AppViewModel.LedgerAttachment(kind: .image, name: "first.png")
        let second = AppViewModel.LedgerAttachment(kind: .screenshot, name: "second.png")
        let item = AppViewModel.LedgerItem(
            title: "References",
            attachments: [file, first, second]
        )

        XCTAssertEqual(item.imageAttachments, [first, second])
        XCTAssertTrue(item.hasImageAttachments)
    }

    func testImageOnlyPresentationExcludesTextTagsAndMixedAttachments() {
        let image = AppViewModel.LedgerAttachment(kind: .image, name: "reference.png")
        let secondImage = AppViewModel.LedgerAttachment(kind: .screenshot, name: "capture.png")
        let file = AppViewModel.LedgerAttachment(kind: .file, name: "brief.pdf")
        let tag = AppViewModel.TagSummary(name: "Reference")

        XCTAssertTrue(AppViewModel.LedgerItem(
            title: "reference.png",
            text: "",
            attachments: [image, secondImage]
        ).displaysOnlyImages)
        XCTAssertFalse(AppViewModel.LedgerItem(
            title: "Image title",
            attachments: [image]
        ).displaysOnlyImages)
        XCTAssertFalse(AppViewModel.LedgerItem(
            title: "@Reference",
            tags: [tag],
            attachments: [image]
        ).displaysOnlyImages)
        XCTAssertFalse(AppViewModel.LedgerItem(
            title: "reference.png",
            text: "",
            attachments: [image, file]
        ).displaysOnlyImages)
    }

    func testEditingTextPreservesImageAttachments() {
        let image = AppViewModel.LedgerAttachment(kind: .image, name: "reference.png")
        let item = AppViewModel.LedgerItem(
            title: "Original",
            text: "Original",
            attachments: [image]
        )
        var hooks = AppViewModel.Hooks()
        hooks.onUpdateText = { _, _ in nil }
        let viewModel = AppViewModel(items: [item], hooks: hooks)

        viewModel.beginEditing(item)
        viewModel.updateEditingDraft("Updated title")

        XCTAssertTrue(viewModel.saveEditing())
        XCTAssertEqual(viewModel.items[0].title, "Updated title")
        XCTAssertEqual(viewModel.items[0].attachments, [image])
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

    private func composerImage(
        name: String,
        contents: String,
        type: UTType = .png
    ) -> AppViewModel.ComposerImage {
        AppViewModel.ComposerImage(
            data: Data(contents.utf8),
            typeIdentifier: type.identifier,
            filename: name
        )
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

    func testLandingResolverUsesCommittedRowFrameForReorder() {
        let itemID = UUID()
        let source = CGRect(x: 0, y: 80, width: 420, height: 48)
        let destination = CGRect(x: 0, y: 240, width: 420, height: 48)
        let target = LedgerReorderTarget(
            targetID: UUID(),
            placement: .after,
            destinationPinned: false
        )

        let landing = LedgerDragLandingResolver.landing(
            for: .reorder(target),
            itemID: itemID,
            sourceFrame: source,
            regions: [.row(itemID): destination]
        )

        XCTAssertEqual(landing, .reorder(destination))
        XCTAssertEqual(landing.targetPosition, CGPoint(x: 165, y: 264))
    }

    func testLandingResolverUsesFolderCenter() {
        let itemID = UUID()
        let folderID = UUID()
        let folderFrame = CGRect(x: 0, y: 30, width: 420, height: 50)

        let landing = LedgerDragLandingResolver.landing(
            for: .folder(folderID),
            itemID: itemID,
            sourceFrame: .zero,
            regions: [.folder(folderID): folderFrame]
        )

        XCTAssertEqual(landing, .folder(folderFrame))
        XCTAssertEqual(landing.targetPosition, CGPoint(x: 210, y: 55))
    }

    func testLandingResolverCancelsToCapturedSourceFrame() {
        let source = CGRect(x: 8, y: 120, width: 420, height: 48)

        XCTAssertEqual(
            LedgerDragLandingResolver.landing(
                for: nil,
                itemID: UUID(),
                sourceFrame: source,
                regions: [:]
            ),
            .cancel(source)
        )
    }

    func testProjectedRelativeVelocityHandlesZeroDistanceAndClamps() {
        XCTAssertEqual(
            LedgerDragLandingResolver.projectedRelativeVelocity(
                velocity: CGSize(width: 900, height: -400),
                from: CGPoint(x: 20, y: 20),
                to: CGPoint(x: 20, y: 20)
            ),
            0
        )
        XCTAssertEqual(
            LedgerDragLandingResolver.projectedRelativeVelocity(
                velocity: CGSize(width: 2_000, height: 0),
                from: .zero,
                to: CGPoint(x: 100, y: 0)
            ),
            1
        )
        XCTAssertEqual(
            LedgerDragLandingResolver.projectedRelativeVelocity(
                velocity: CGSize(width: -2_000, height: 0),
                from: .zero,
                to: CGPoint(x: 100, y: 0)
            ),
            -1
        )
    }

    func testLandingCleanupRejectsAStaleGeneration() {
        XCTAssertTrue(LedgerDragLandingResolver.shouldCleanUp(
            completionGeneration: 8,
            currentGeneration: 8
        ))
        XCTAssertFalse(LedgerDragLandingResolver.shouldCleanUp(
            completionGeneration: 7,
            currentGeneration: 8
        ))
    }
}
