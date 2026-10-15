import AppKit
import Foundation
import NotchCaptureSync
import SwiftData
import XCTest
@testable import NotchCapture

@MainActor
final class NestedFolderTests: XCTestCase {
    private enum SaveFailure: Error { case injected }

    private func container() throws -> ModelContainer {
        let schema = Schema(NotchCaptureSchemaV3.models)
        return try ModelContainer(for: schema, migrationPlan: NotchCaptureMigrationPlan.self,
                                  configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func testNamesAreUniqueAmongSiblingsAndParentsMustExist() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let work = try repository.createList(name: "Work")
        let home = try repository.createList(name: "Home")
        let research = try repository.createList(name: " Research ", parentID: work.id)
        let otherResearch = try repository.createList(name: "Research", parentID: home.id)
        XCTAssertEqual(research.name, "Research")
        XCTAssertEqual(research.parentID, work.id)
        XCTAssertEqual(research.sortOrder, otherResearch.sortOrder)
        XCTAssertThrowsError(try repository.createList(name: "research", parentID: work.id))
        XCTAssertThrowsError(try repository.createList(name: "Lost", parentID: UUID()))
        let sibling = try repository.createList(name: "Drafts", parentID: work.id)
        XCTAssertThrowsError(try repository.renameList(sibling, to: "RESEARCH"))
        try repository.renameList(sibling, to: "Home")
        XCTAssertEqual(sibling.name, home.name)
    }

    func testMovesPreserveSubtreeAndRejectCyclesOrNameConflicts() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let root = try repository.createList(name: "Work")
        let child = try repository.createList(name: "Research", parentID: root.id)
        let grandchild = try repository.createList(name: "Drafts", parentID: child.id)
        let destination = try repository.createList(name: "Personal")
        let existing = try repository.createList(name: "Existing", parentID: destination.id)
        let item = try repository.createItem(text: "Keep", origin: .manual, list: grandchild)
        XCTAssertThrowsError(try repository.moveList(root, to: root.id))
        XCTAssertThrowsError(try repository.moveList(root, to: grandchild.id))
        XCTAssertThrowsError(try repository.moveList(child, to: UUID()))
        try repository.moveList(child, to: destination.id)
        XCTAssertEqual(child.parentID, destination.id)
        XCTAssertGreaterThan(child.sortOrder, existing.sortOrder)
        XCTAssertEqual(grandchild.parentID, child.id)
        XCTAssertEqual(item.list?.id, grandchild.id)
        _ = try repository.createList(name: "Research", parentID: root.id)
        XCTAssertThrowsError(try repository.moveList(child, to: root.id))
        try repository.moveList(child, to: nil)
        XCTAssertNil(child.parentID)
    }

    func testDeletePromotesDirectContentsAndResolvesSiblingNames() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let parent = try repository.createList(name: "Work")
        let deleted = try repository.createList(name: "Project", parentID: parent.id)
        let existing = try repository.createList(name: "Research", parentID: parent.id)
        let promoted = try repository.createList(name: "Research", parentID: deleted.id)
        let deeper = try repository.createList(name: "Drafts", parentID: promoted.id)
        let alreadyHere = try repository.createItem(text: "Existing", origin: .manual, list: parent)
        let first = try repository.createItem(text: "First", origin: .manual, list: deleted)
        let second = try repository.createItem(text: "Second", origin: .manual, list: deleted)
        let pinned = try repository.createItem(text: "Pinned", origin: .manual, list: deleted)
        try repository.setPinned(true, for: pinned)
        let nested = try repository.createItem(text: "Nested", origin: .manual, list: deeper)
        XCTAssertEqual(try repository.deleteList(deleted), 3)
        XCTAssertEqual(promoted.parentID, parent.id)
        XCTAssertEqual(promoted.name, "Research (2)")
        XCTAssertGreaterThan(promoted.sortOrder, existing.sortOrder)
        XCTAssertEqual(deeper.parentID, promoted.id)
        XCTAssertEqual(nested.list?.id, deeper.id)
        XCTAssertEqual(first.list?.id, parent.id)
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.list?.id, parent.id)
        XCTAssertLessThan(try XCTUnwrap(first.sortOrder), try XCTUnwrap(second.sortOrder))
        XCTAssertLessThan(try XCTUnwrap(second.sortOrder), try XCTUnwrap(alreadyHere.sortOrder))
        try repository.deleteList(parent)
        XCTAssertNil(promoted.parentID)
        XCTAssertNil(first.list)
        XCTAssertEqual(deeper.parentID, promoted.id)
    }

    func testFolderTransactionsRollBackOnSaveFailure() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let root = try repository.createList(name: "Root")
        let child = try repository.createList(name: "Child", parentID: root.id)
        _ = try repository.createItem(text: "Keep", origin: .manual, list: root)
        let rootID = root.id
        let childID = child.id
        let failing = ItemRepository(modelContext: store.mainContext, saveHandler: { throw SaveFailure.injected })
        func folder(_ id: UUID) throws -> ItemList {
            try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<ItemList>()).first { $0.id == id })
        }
        // Rollback invalidates registered SwiftData instances. Resolve again as the coordinator does.
        XCTAssertThrowsError(try failing.createList(name: "New", parentID: rootID))
        XCTAssertThrowsError(try failing.moveList(folder(childID), to: nil))
        XCTAssertEqual(try folder(childID).parentID, rootID)
        XCTAssertThrowsError(try failing.renameList(folder(childID), to: "Renamed"))
        XCTAssertEqual(try folder(childID).name, "Child")
        XCTAssertThrowsError(try failing.deleteList(folder(rootID)))
        XCTAssertFalse(store.mainContext.hasChanges)
        let fresh = ModelContext(store)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<ItemList>()).count, 2)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CaptureItem>()).first?.list?.id, rootID)
    }

    func testReorderingOnlyChangesSiblingsAtTheCurrentLevel() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let parent = try repository.createList(name: "Root")
        let first = try repository.createList(name: "First", parentID: parent.id)
        let second = try repository.createList(name: "Second", parentID: parent.id)
        try repository.applyFolderOrderAssignments([
            FolderOrderAssignment(id: second.id, sortOrder: 0),
            FolderOrderAssignment(id: first.id, sortOrder: 1),
        ])
        XCTAssertThrowsError(try repository.applyFolderOrderAssignments([
            FolderOrderAssignment(id: parent.id, sortOrder: 8),
            FolderOrderAssignment(id: first.id, sortOrder: 9),
        ]))
        XCTAssertEqual(parent.sortOrder, 0)
        let summaries = [parent, first, second].map {
            AppViewModel.FolderSummary(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, parentID: $0.parentID)
        }
        let model = AppViewModel(folders: summaries)
        model.openFolder(summaries[0])
        XCTAssertTrue(model.reorderFolder(folderID: first.id, relativeTo: second.id, placement: .before))
        XCTAssertEqual(model.visibleFolders.map(\.id), [first.id, second.id])
        XCTAssertFalse(model.reorderFolder(folderID: first.id, relativeTo: parent.id, placement: .before))
    }

    func testBrowsingSearchPathsAndParentNavigation() {
        let parent = AppViewModel.FolderSummary(name: "Work")
        let child = AppViewModel.FolderSummary(name: "Research", parentID: parent.id)
        let grandchild = AppViewModel.FolderSummary(name: "Drafts", parentID: child.id)
        let direct = AppViewModel.LedgerItem(title: "Find direct", folderID: parent.id)
        let nested = AppViewModel.LedgerItem(title: "Find nested", folderID: grandchild.id)
        let model = AppViewModel(surfaceState: .expanded, items: [direct, nested],
                                 folders: [parent, child, grandchild], isFolderSectionExpanded: true)
        XCTAssertEqual(model.visibleFolders.map(\.id), [parent.id])
        model.openFolder(parent)
        XCTAssertEqual(model.visibleFolders.map(\.id), [child.id])
        XCTAssertEqual(model.visibleItems.map(\.id), [direct.id])
        model.composerText = "Work"
        XCTAssertTrue(model.visibleFolders.isEmpty)
        model.composerText = "Find"
        XCTAssertEqual(model.visibleItems.map(\.id), [direct.id])
        model.composerSearchesAllFolders = true
        XCTAssertEqual(Set(model.visibleItems.map(\.id)), Set([direct.id, nested.id]))
        model.composerText = "Drafts"
        XCTAssertEqual(model.visibleFolders.map(\.id), [grandchild.id])
        XCTAssertEqual(model.folderPath(for: grandchild), "Work / Research / Drafts")
        model.openFolder(grandchild)
        model.handleDismissalRequest(.escape)
        XCTAssertEqual(model.browseLocation, .folder(child.id))
        XCTAssertTrue(model.isNavigatingToParent)
        model.openParent()
        XCTAssertEqual(model.browseLocation, .folder(parent.id))
        model.openParent()
        XCTAssertTrue(model.isAtRoot)
        model.composerText = "Drafts"
        XCTAssertEqual(model.visibleFolders.map(\.id), [grandchild.id])
        model.isScreenSharePrivacyEnabled = true
        let path = model.folderPath(for: grandchild)
        XCTAssertFalse(path.contains("Work"))
        XCTAssertFalse(path.contains("Research"))
        XCTAssertFalse(path.contains("Drafts"))
        XCTAssertEqual(path.components(separatedBy: " / ").count, 3)
    }

    func testCreationUsesCurrentFolderEvenDuringGlobalSearch() {
        let root = AppViewModel.FolderSummary(name: "Work")
        var parents: [UUID?] = []
        var hooks = AppViewModel.Hooks()
        hooks.onCreateFolder = { _, parentID in parents.append(parentID); return UUID() }
        let model = AppViewModel(folders: [root], hooks: hooks)
        model.openFolder(root)
        model.composerSearchesAllFolders = true
        XCTAssertTrue(model.createFolder(named: "Dialog"))
        XCTAssertEqual(model.browseLocation, .folder(root.id))
        model.composerText = "/folder Command"
        model.submitComposer()
        XCTAssertEqual(parents, [root.id, root.id])
        XCTAssertEqual(model.currentFolder?.name, "Command")
        XCTAssertEqual(model.currentFolder?.parentID, root.id)
        XCTAssertEqual(model.folders.first { $0.name == "Dialog" }?.parentID, root.id)
    }

    func testKeyboardTraversalIncludesImmediateSubfolders() {
        let root = AppViewModel.FolderSummary(name: "Work")
        let child = AppViewModel.FolderSummary(name: "Research", parentID: root.id)
        let nested = AppViewModel.FolderSummary(name: "Drafts", parentID: child.id)
        let model = AppViewModel(folders: [root, child, nested], isFolderSectionExpanded: true)
        model.openFolder(root)
        model.moveLedgerSelection(by: 1)
        XCTAssertEqual(model.selectedFolderID, child.id)
        XCTAssertTrue(model.activateSelectedRow())
        XCTAssertEqual(model.browseLocation, .folder(child.id))
        XCTAssertEqual(model.visibleFolders.map(\.id), [nested.id])
    }

    func testMoveDestinationsExcludeSubtreeAndFailuresLeaveLocationIntact() {
        let root = AppViewModel.FolderSummary(name: "Work")
        let child = AppViewModel.FolderSummary(name: "Research", parentID: root.id)
        let grandchild = AppViewModel.FolderSummary(name: "Drafts", parentID: child.id)
        let destination = AppViewModel.FolderSummary(name: "Personal")
        var hooks = AppViewModel.Hooks()
        hooks.onMoveFolder = { _, _ in "Save failed" }
        hooks.onDeleteFolder = { _ in "Save failed" }
        let model = AppViewModel(folders: [root, child, grandchild, destination], hooks: hooks)
        XCTAssertEqual(model.moveDestinations(for: root).map(\.id), [destination.id])
        model.openFolder(child)
        model.composerText = "Keep draft"
        XCTAssertFalse(model.moveFolder(root, to: grandchild.id))
        XCTAssertFalse(model.moveFolder(child, to: destination.id))
        XCTAssertFalse(model.deleteFolder(child))
        XCTAssertEqual(model.currentFolder?.id, child.id)
        XCTAssertEqual(model.currentFolder?.parentID, root.id)
        XCTAssertEqual(model.composerText, "Keep draft")
        XCTAssertEqual(model.errorMessage, "Save failed")
    }

    func testDeletionProjectionMatchesPersistenceAndReturnsToParent() {
        let root = AppViewModel.FolderSummary(name: "Work")
        let child = AppViewModel.FolderSummary(name: "Project", parentID: root.id)
        let sibling = AppViewModel.FolderSummary(name: "Research", parentID: root.id)
        let promoted = AppViewModel.FolderSummary(name: "Research", parentID: child.id)
        let deep = AppViewModel.FolderSummary(name: "Drafts", parentID: promoted.id)
        let item = AppViewModel.LedgerItem(title: "Keep", folderID: child.id)
        let model = AppViewModel(items: [item], folders: [root, child, sibling, promoted, deep])
        model.openFolder(child)
        XCTAssertTrue(model.deleteFolder(child))
        XCTAssertEqual(model.currentFolder?.id, root.id)
        XCTAssertEqual(model.items[0].folderID, root.id)
        XCTAssertEqual(model.folders.first { $0.id == promoted.id }?.parentID, root.id)
        XCTAssertEqual(model.folders.first { $0.id == promoted.id }?.name, "Research (2)")
        XCTAssertEqual(model.folders.first { $0.id == deep.id }?.parentID, promoted.id)
    }

    func testParentTransitionAndReducedMotion() {
        let parent = FolderNavigationMotionPlan.resolve(for: .folder(UUID()), reduceMotion: false, navigatingToParent: true)
        let child = FolderNavigationMotionPlan.resolve(for: .folder(UUID()), reduceMotion: false)
        XCTAssertLessThan(parent.offset, 0)
        XCTAssertGreaterThan(child.offset, 0)
        XCTAssertEqual(FolderNavigationMotionPlan.resolve(for: .folder(UUID()), reduceMotion: true, navigatingToParent: true).offset, 0)
    }

    func testCompanionResolvesFolderIdentityWithoutFlatteningOrNameMerging() throws {
        let store = try container()
        let repository = ItemRepository(modelContext: store.mainContext)
        let root = try repository.createList(name: "Work")
        let child = try repository.createList(name: "Research", parentID: root.id)
        var lists = [root, child]
        let known = CaptureRecord(text: "Known", folderID: child.id, folderName: child.name)
        let resolved = CompanionSyncService.resolveList(for: known, in: &lists, modelContext: store.mainContext)
        XCTAssertEqual(resolved?.id, child.id)
        XCTAssertEqual(resolved?.parentID, root.id)
        let newID = UUID()
        let unknown = CaptureRecord(text: "Unknown", folderID: newID, folderName: child.name)
        let newFolder = CompanionSyncService.resolveList(for: unknown, in: &lists, modelContext: store.mainContext)
        XCTAssertEqual(newFolder?.id, newID)
        XCTAssertNil(newFolder?.parentID)
        XCTAssertNotEqual(newFolder?.id, child.id)
    }

    func testV2StoreMigratesWithoutLosingFolderMembership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.store")
        let folderID = UUID()
        let itemID = UUID()
        try populateV2Store(at: url, folderID: folderID, itemID: itemID)
        let schema = Schema(NotchCaptureSchemaV3.models)
        let store = try ModelContainer(for: schema, migrationPlan: NotchCaptureMigrationPlan.self,
            configurations: [ModelConfiguration("NotchCapture", schema: schema, url: url)])
        let folders = try store.mainContext.fetch(FetchDescriptor<ItemList>())
        XCTAssertEqual(folders.map(\.id), [folderID])
        XCTAssertNil(folders[0].parentID)
        let item = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<CaptureItem>()).first)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.list?.id, folderID)
        XCTAssertEqual(item.tags.first?.name, "Work")
        XCTAssertEqual(item.attachments.first?.originalFilename, "keep.txt")
        XCTAssertEqual(item.sortOrder, 7)
        let child = try ItemRepository(modelContext: store.mainContext).createList(name: "Child", parentID: folderID)
        let reopened = try ModelContainer(for: schema, migrationPlan: NotchCaptureMigrationPlan.self,
            configurations: [ModelConfiguration("NotchCapture", schema: schema, url: url)])
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<ItemList>()).first { $0.id == child.id }?.parentID, folderID)
    }

    func testDeepHierarchyHasNoNavigationOrTraversalLimit() {
        var folders: [AppViewModel.FolderSummary] = []
        for index in 0..<100 {
            folders.append(AppViewModel.FolderSummary(name: "Level \(index)", parentID: folders.last?.id))
        }
        let model = AppViewModel(folders: folders)
        XCTAssertEqual(model.descendantFolderIDs(of: folders[0].id).count, 99)
        XCTAssertEqual(model.folderPath(for: folders[99]).components(separatedBy: " / ").count, 100)
        model.openFolder(folders[99])
        for index in (0..<99).reversed() {
            model.openParent()
            XCTAssertEqual(model.currentFolder?.id, folders[index].id)
        }
        model.openParent()
        XCTAssertTrue(model.isAtRoot)
    }

    private func populateV2Store(at url: URL, folderID: UUID, itemID: UUID) throws {
        let schema = Schema(NotchCaptureSchemaV2.models)
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration("NotchCapture", schema: schema, url: url)])
        let folder = NotchCaptureSchemaV2.ItemList(id: folderID, name: "Projects")
        let tag = NotchCaptureSchemaV2.CaptureTag(name: "Work")
        let attachment = NotchCaptureSchemaV2.Attachment(kind: .file, typeIdentifier: "public.text", originalFilename: "keep.txt")
        let item = NotchCaptureSchemaV2.CaptureItem(id: itemID, text: "Keep", sortOrder: 7, list: folder, tags: [tag], attachments: [attachment])
        store.mainContext.insert(item)
        try store.mainContext.save()
    }
}
