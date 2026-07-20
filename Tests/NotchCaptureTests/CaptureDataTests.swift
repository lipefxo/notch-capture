import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import NotchCapture

@MainActor
final class CaptureDataTests: XCTestCase {
    func testTagParserExtractsIntentionalTokensAndPreservesReadableText() {
        let parsed = CaptureTagParser.parse("Review draft @Lipe @Product-Launch\nEmail lipe@example.com @2026")

        XCTAssertEqual(parsed.text, "Review draft\nEmail lipe@example.com")
        XCTAssertEqual(parsed.tagNames, ["Lipe", "Product-Launch", "2026"])
        XCTAssertEqual(CaptureTagParser.parse("@Lipe @lipe").tagNames, ["Lipe"])
        XCTAssertEqual(CaptureTagParser.parse("@João @project_one,").tagNames, ["João", "project_one"])
        XCTAssertEqual(CaptureTagParser.parse("Bare @").tagNames, [])
        XCTAssertEqual(CaptureTagParser.activeTagFragment(in: "Plan @Product"), "Product")
        XCTAssertNil(CaptureTagParser.activeTagFragment(in: "lipe@example"))
        XCTAssertEqual(
            CaptureTagParser.removingTagMentions(
                in: "Send @Lipe to @Home at lipe@example.com",
                matching: ["lipe"]
            ),
            "Send to @Home at lipe@example.com"
        )
        XCTAssertEqual(
            CaptureTagParser.replacingTagMentions(
                in: "Ask @LIPE, not lipe@example.com or @Home",
                matching: "lipe",
                with: "People"
            ),
            "Ask @People, not lipe@example.com or @Home"
        )

        let taggedURL = CaptureTagParser.parse("www.example.com @Reading")
        XCTAssertEqual(taggedURL.text, "www.example.com")
        XCTAssertEqual(CaptureURLParser.url(from: taggedURL.text)?.absoluteString, "https://www.example.com")
    }

    func testTagRepositoryCreatesMergesAndDetachesTags() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let item = try repository.createItem(
            text: "Review draft with @Lipe",
            origin: .manual,
            tagNames: ["Lipe", "lipe"]
        )
        let work = try repository.createTag(name: "Work")

        XCTAssertEqual(item.tags.map(\.name), ["Lipe"])
        XCTAssertTrue(try XCTUnwrap(item.tags.first?.colorSeed) >= 0)
        XCTAssertTrue(try XCTUnwrap(item.tags.first?.colorSeed) < 1)
        XCTAssertEqual(Set(try repository.fetchTags().map(\.name)), Set(["Lipe", "Work"]))
        XCTAssertEqual(try repository.fetch(scope: .inbox, search: "@lipe").map(\.id), [item.id])
        XCTAssertEqual(try repository.fetch(scope: .inbox, search: "Review @work").map(\.id), [])
        XCTAssertEqual(try repository.fetch(scope: .inbox, search: "Lipe").map(\.id), [])

        let lipe = try XCTUnwrap(item.tags.first)
        let merged = try repository.renameTag(lipe, to: "work")
        XCTAssertEqual(merged.id, work.id)
        XCTAssertEqual(item.tags.map(\.id), [work.id])
        XCTAssertEqual(item.text, "Review draft with @Work")
        XCTAssertEqual(try repository.fetchTags().count, 1)

        try repository.deleteTag(work)
        XCTAssertTrue(item.tags.isEmpty)
        XCTAssertEqual(item.text, "Review draft with @Work")
        XCTAssertTrue(try repository.fetchTags().isEmpty)
        XCTAssertEqual(try repository.fetch(scope: .inbox, search: "Work").map(\.id), [item.id])
    }

    func testEmbeddedTagCreationPreservesTextAndReusesNamesCaseInsensitively() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let existing = try repository.createTag(name: "Home")
        let text = "I want to create a new task for @home that is this xyz"
        let parsed = CaptureTagParser.parse(text)

        let item = try repository.createItem(
            text: text,
            origin: .manual,
            tagNames: parsed.tagNames
        )

        XCTAssertEqual(item.text, text)
        XCTAssertEqual(item.tags.map(\.id), [existing.id])
        XCTAssertEqual(item.tags.map(\.name), ["Home"])
        XCTAssertEqual(try repository.fetchTags().count, 1)
        XCTAssertTrue(try repository.fetch(scope: .inbox, search: "home").isEmpty)
        XCTAssertEqual(try repository.fetch(scope: .inbox, search: "@HOME").map(\.id), [item.id])
        XCTAssertEqual(
            try repository.fetch(scope: .inbox, search: "new task @home").map(\.id),
            [item.id]
        )

        let newText = "Put the tools in @Garden"
        let newTagItem = try repository.createItem(
            text: newText,
            origin: .manual,
            tagNames: CaptureTagParser.parse(newText).tagNames
        )
        XCTAssertEqual(newTagItem.text, newText)
        XCTAssertEqual(newTagItem.tags.map(\.name), ["Garden"])
        XCTAssertEqual(try repository.fetchTags().count, 2)

        let renamed = try repository.renameTag(existing, to: "HOMEBASE")
        XCTAssertEqual(renamed.name, "HOMEBASE")
        XCTAssertEqual(item.text, "I want to create a new task for @HOMEBASE that is this xyz")
    }

    func testLegacyTagsReceivePersistentColorSeeds() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let legacy = CaptureTag(name: "Legacy", colorSeed: nil)
        container.mainContext.insert(legacy)
        try container.mainContext.save()

        XCTAssertTrue(try repository.backfillMissingTagColorSeeds())
        let assigned = try XCTUnwrap(legacy.colorSeed)
        XCTAssertTrue((0..<1).contains(assigned))
        XCTAssertFalse(try repository.backfillMissingTagColorSeeds())
        XCTAssertEqual(legacy.colorSeed, assigned)
    }

    func testItemSemanticsAndRepositoryScopes() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let note = try repository.createItem(text: "First line\nMore detail", origin: .manual)

        XCTAssertEqual(note.displayTitle, "First line")
        XCTAssertEqual(try repository.fetch(scope: .inbox).map(\.id), [note.id])

        try repository.setDueDate(Date(timeIntervalSince1970: 1_700_050_000), for: note, calendar: utcCalendar)
        XCTAssertEqual(note.kind, .task)
        XCTAssertEqual(note.dueDate, utcCalendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_050_000)))
        XCTAssertEqual(try repository.fetch(scope: .tasks).map(\.id), [note.id])
        XCTAssertEqual(try repository.fetch(scope: .due).map(\.id), [note.id])

        let completedAt = Date(timeIntervalSince1970: 1_700_100_000)
        try repository.setCompleted(true, for: note, at: completedAt)
        XCTAssertEqual(note.completedAt, completedAt)
        XCTAssertEqual(
            try repository.fetch(
                scope: .inbox,
                now: completedAt.addingTimeInterval(CompletionVisibility.mainPageRetention - 1)
            ).map(\.id),
            [note.id]
        )
        XCTAssertTrue(
            try repository.fetch(
                scope: .inbox,
                now: completedAt.addingTimeInterval(CompletionVisibility.mainPageRetention)
            ).isEmpty
        )
        XCTAssertEqual(try repository.fetch(scope: .completed).map(\.id), [note.id])

        try repository.setCompleted(false, for: note)
        XCTAssertNil(note.completedAt)
        try repository.setCompleted(true, for: note, at: completedAt)

        try repository.trash(note)
        XCTAssertEqual(try repository.fetch(scope: .trash).map(\.id), [note.id])
        try repository.restore(note)
        XCTAssertEqual(try repository.fetch(scope: .completed).map(\.id), [note.id])
    }

    func testTrashCompletedTasksIsGlobalRecoverableAndPreservesAttachments() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)
        let completedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let clearedAt = Date(timeIntervalSince1970: 1_700_200_000)

        let completedWithImage = try repository.createItem(
            from: .image(Data("pixels".utf8), typeIdentifier: UTType.png.identifier),
            origin: .manual
        )
        try repository.setKind(.task, for: completedWithImage)
        try repository.setCompleted(true, for: completedWithImage, at: completedAt)
        let storedPath = try XCTUnwrap(completedWithImage.attachments.first?.relativePath)

        let archivedCompleted = try repository.createItem(text: "Archived done", origin: .manual)
        try repository.setKind(.task, for: archivedCompleted)
        try repository.setCompleted(true, for: archivedCompleted, at: completedAt)
        try repository.archive(archivedCompleted)

        let incomplete = try repository.createItem(text: "Still open", origin: .manual)
        try repository.setKind(.task, for: incomplete)

        let alreadyTrashed = try repository.createItem(text: "Already trashed", origin: .manual)
        try repository.setKind(.task, for: alreadyTrashed)
        try repository.setCompleted(true, for: alreadyTrashed, at: completedAt)
        try repository.trash(alreadyTrashed, at: completedAt)

        XCTAssertEqual(try repository.trashCompletedTasks(at: clearedAt), 2)

        XCTAssertEqual(completedWithImage.trashedAt, clearedAt)
        XCTAssertEqual(completedWithImage.updatedAt, clearedAt)
        XCTAssertEqual(archivedCompleted.trashedAt, clearedAt)
        XCTAssertNil(incomplete.trashedAt)
        XCTAssertEqual(alreadyTrashed.trashedAt, completedAt)
        XCTAssertTrue(try repository.fetch(scope: .completed).isEmpty)
        XCTAssertEqual(
            Set(try repository.fetch(scope: .trash).map(\.id)),
            Set([completedWithImage.id, archivedCompleted.id, alreadyTrashed.id])
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try store.resolve(relativePath: storedPath).path
            )
        )
        XCTAssertEqual(try repository.trashCompletedTasks(at: clearedAt), 0)

        try repository.restore(completedWithImage)
        XCTAssertEqual(try repository.fetch(scope: .completed).map(\.id), [completedWithImage.id])
    }

    func testEmptyCaptureIsRejected() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        XCTAssertThrowsError(try repository.createItem(text: "  \n", origin: .manual)) { error in
            guard case ItemRepositoryError.emptyCapture = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUpdatingTextPreservesExactContentAndSynchronizesTags() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let home = try repository.createTag(name: "Home")
        let item = try repository.createItem(
            text: "Old content @Work",
            origin: .manual,
            tagNames: ["Work"]
        )
        let work = try XCTUnwrap(item.tags.first)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 42_000)
        let edited = "  First line  \n\nSecond line @home @New @new"

        try repository.updateText(item, text: edited, now: updatedAt)

        XCTAssertEqual(item.text, edited)
        XCTAssertEqual(item.updatedAt, updatedAt)
        XCTAssertEqual(Set(item.tags.map(\.id)), Set([home.id, try XCTUnwrap(
            repository.fetchTags().first(where: { $0.normalizedName == "new" })
        ).id]))
        XCTAssertFalse(item.tags.contains(where: { $0.id == work.id }))
        XCTAssertTrue(try repository.fetchTags().contains(where: { $0.id == work.id }))
    }

    func testUpdatingTextRejectsEmptyTextWithoutChangingTextOnlyItem() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let item = try repository.createItem(
            text: "Keep this @Work",
            origin: .manual,
            tagNames: ["Work"]
        )
        let originalTagIDs = item.tags.map(\.id)
        let originalUpdatedAt = item.updatedAt

        XCTAssertThrowsError(try repository.updateText(item, text: " \n ")) { error in
            guard case ItemRepositoryError.emptyCapture = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(item.text, "Keep this @Work")
        XCTAssertEqual(item.tags.map(\.id), originalTagIDs)
        XCTAssertEqual(item.updatedAt, originalUpdatedAt)
    }

    func testAttachmentBackedItemCanBeUpdatedToEmptyText() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let item = try repository.createItem(from: .mixed(text: "A caption", urls: [url]), origin: .drop)

        try repository.updateText(item, text: "")

        XCTAssertTrue(item.text.isEmpty)
        XCTAssertEqual(item.attachments.count, 1)
        XCTAssertTrue(item.tags.isEmpty)
    }

    func testAttachmentStoreRejectsTraversal() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        XCTAssertThrowsError(try store.resolve(relativePath: "../outside"))
    }

    func testOrphanedAttachmentFilesAreSweptWhileReferencedAndHiddenFilesSurvive() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)

        let item = try repository.createItem(
            from: .image(Data("pixels".utf8), typeIdentifier: UTType.png.identifier),
            origin: .screenshot
        )
        let referencedPath = try XCTUnwrap(item.attachments.first?.relativePath)
        let orphan = temporary.appendingPathComponent("orphan.png")
        try Data("stale".utf8).write(to: orphan)
        let hidden = temporary.appendingPathComponent(".inflight.tmp")
        try Data("copying".utf8).write(to: hidden)

        let removed = try repository.removeOrphanedAttachmentFiles()

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hidden.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.resolve(relativePath: referencedPath).path))
    }

    func testDeletePermanentlyRemovesAttachmentFilesFromDisk() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)

        let item = try repository.createItem(
            from: .image(Data("pixels".utf8), typeIdentifier: UTType.png.identifier),
            origin: .screenshot
        )
        let path = try XCTUnwrap(item.attachments.first?.relativePath)
        let fileURL = try store.resolve(relativePath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try repository.deletePermanently(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(try repository.fetch(scope: .trash).isEmpty)
        XCTAssertTrue(try repository.fetch(scope: .inbox).isEmpty)
    }

    func testPayloadMaterializationStoresImageAndURLAttachments() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)

        let image = try repository.createItem(
            from: .image(Data("pixels".utf8), typeIdentifier: UTType.png.identifier),
            origin: .screenshot
        )
        XCTAssertEqual(image.attachments.first?.kind, .screenshot)
        let path = try XCTUnwrap(image.attachments.first?.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.resolve(relativePath: path).path))

        let link = try repository.createItem(
            from: .url(try XCTUnwrap(URL(string: "https://example.com/read"))),
            origin: .drop
        )
        XCTAssertEqual(link.attachments.first?.kind, .url)
        XCTAssertEqual(link.displayTitle, "example.com")
    }

    func testComposerImagePayloadsPersistInOrderWithTextTagsAndFolder() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)
        let list = try repository.createList(name: "Projects")

        let item = try repository.createItem(
            text: "Review @Work",
            origin: .manual,
            list: list,
            tagNames: ["Work"],
            imageAttachments: [
                ImageAttachmentPayload(
                    data: Data("first".utf8),
                    typeIdentifier: UTType.png.identifier,
                    filename: "First.png"
                ),
                ImageAttachmentPayload(
                    data: Data("second".utf8),
                    typeIdentifier: UTType.jpeg.identifier,
                    filename: "Second.jpg"
                ),
            ]
        )

        XCTAssertEqual(item.list?.id, list.id)
        XCTAssertEqual(item.tags.map(\.name), ["Work"])
        let orderedAttachments = item.attachments.sorted { $0.order < $1.order }
        XCTAssertEqual(orderedAttachments.map(\.order), [0, 1])
        XCTAssertEqual(orderedAttachments.map(\.originalFilename), ["First.png", "Second.jpg"])
        XCTAssertEqual(orderedAttachments.map(\.kind), [.image, .image])
        for attachment in orderedAttachments {
            let path = try XCTUnwrap(attachment.relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try store.resolve(relativePath: path).path))
        }
    }

    func testComposerImagePayloadFailureRemovesPartiallyStoredFiles() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext, attachmentStore: store)

        XCTAssertThrowsError(
            try repository.createItem(
                text: "Keep this draft",
                origin: .manual,
                imageAttachments: [
                    ImageAttachmentPayload(
                        data: Data("first".utf8),
                        typeIdentifier: UTType.png.identifier,
                        filename: "First.png"
                    ),
                    ImageAttachmentPayload(
                        data: Data(),
                        typeIdentifier: UTType.png.identifier,
                        filename: "Empty.png"
                    ),
                ]
            )
        )

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CaptureItem>()).isEmpty)
    }

    func testPlainWebAddressesBecomeURLAttachments() throws {
        XCTAssertEqual(
            CaptureURLParser.url(from: "  www.youtube.com/watch?v=123  ")?.absoluteString,
            "https://www.youtube.com/watch?v=123"
        )
        XCTAssertEqual(
            CaptureURLParser.url(from: "https://example.com/read")?.absoluteString,
            "https://example.com/read"
        )
        XCTAssertNil(CaptureURLParser.url(from: "Watch www.youtube.com"))
        XCTAssertNil(CaptureURLParser.url(from: "ftp://example.com"))

        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let url = try XCTUnwrap(CaptureURLParser.url(from: "www.youtube.com"))
        let item = try repository.createItem(from: .url(url), origin: .manual)

        XCTAssertTrue(item.text.isEmpty)
        XCTAssertEqual(item.attachments.map(\.kind), [.url])
        XCTAssertEqual(item.attachments.first?.url?.absoluteString, "https://www.youtube.com")
        XCTAssertEqual(item.displayTitle, "www.youtube.com")
    }

    func testNewItemsEnterAtBottomAndAssignmentsPersistAtomically() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let first = try repository.createItem(text: "First", origin: .manual)
        let second = try repository.createItem(text: "Second", origin: .manual)

        XCTAssertEqual(try repository.fetch(scope: .inbox).map(\.id), [first.id, second.id])

        try repository.applyOrderAssignments([
            ItemOrderAssignment(id: first.id, isPinned: true, sortOrder: 0),
            ItemOrderAssignment(id: second.id, isPinned: false, sortOrder: 0),
        ])

        let fetched = try repository.fetch(scope: .inbox)
        XCTAssertEqual(fetched.map(\.id), [first.id, second.id])
        XCTAssertTrue(fetched[0].isPinned)
        XCTAssertEqual(fetched[0].sortOrder, 0)
        XCTAssertEqual(fetched[1].sortOrder, 0)
    }

    func testFolderCreationRenameAndDuplicateValidation() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let folder = try repository.createList(name: "  Research  ")

        XCTAssertEqual(folder.name, "Research")
        XCTAssertThrowsError(try repository.createList(name: "research")) { error in
            guard case ItemRepositoryError.duplicateListName = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        try repository.renameList(folder, to: "Reading")
        XCTAssertEqual(folder.name, "Reading")
        XCTAssertThrowsError(try repository.renameList(folder, to: " \n ")) { error in
            guard case ItemRepositoryError.emptyListName = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFolderScopedOrderingAllowsEqualRanksAcrossContainers() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let folder = try repository.createList(name: "Work")
        let inboxItem = try repository.createItem(text: "Inbox", origin: .manual)
        let folderItem = try repository.createItem(text: "Folder", origin: .manual, list: folder)

        XCTAssertEqual(inboxItem.sortOrder, folderItem.sortOrder)
        XCTAssertFalse(try repository.backfillMissingSortOrders())

        let newerFolderItem = try repository.createItem(text: "Newer folder item", origin: .manual, list: folder)
        XCTAssertGreaterThan(try XCTUnwrap(newerFolderItem.sortOrder), try XCTUnwrap(folderItem.sortOrder))
        XCTAssertNil(inboxItem.list)
        XCTAssertEqual(folderItem.list?.id, folder.id)
    }

    func testFolderOrderAssignmentsPersistWithoutChangingFolderContents() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let first = try repository.createList(name: "First")
        let second = try repository.createList(name: "Second")
        let item = try repository.createItem(text: "Keep me here", origin: .manual, list: first)

        try repository.applyFolderOrderAssignments([
            FolderOrderAssignment(id: second.id, sortOrder: 0),
            FolderOrderAssignment(id: first.id, sortOrder: 1),
        ])

        let folders = try container.mainContext.fetch(
            FetchDescriptor<ItemList>(sortBy: [SortDescriptor(\ItemList.sortOrder)])
        )
        XCTAssertEqual(folders.map(\.id), [second.id, first.id])
        XCTAssertEqual(item.list?.id, first.id)
    }

    func testMovingAndDeletingFolderPreservesItemsAndRelativeOrder() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let folder = try repository.createList(name: "Projects")
        let existingInbox = try repository.createItem(text: "Existing inbox", origin: .manual)
        let first = try repository.createItem(text: "First", origin: .manual, list: folder)
        let second = try repository.createItem(text: "Second", origin: .manual, list: folder)

        try repository.move(existingInbox, to: folder)
        XCTAssertEqual(existingInbox.list?.id, folder.id)
        XCTAssertEqual(try repository.fetch(scope: .list(folder.id)).first?.id, existingInbox.id)

        XCTAssertEqual(try repository.deleteList(folder), 3)

        let storedFolders = try container.mainContext.fetch(FetchDescriptor<ItemList>())
        XCTAssertTrue(storedFolders.isEmpty)
        let inbox = try repository.fetch(scope: .inbox)
        XCTAssertEqual(inbox.map(\.id), [existingInbox.id, first.id, second.id])
        XCTAssertTrue(inbox.allSatisfy { $0.list == nil })
    }

    func testMissingReorderItemDoesNotPartiallyApplyAssignments() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let item = try repository.createItem(text: "Existing", origin: .manual)
        let originalRank = item.sortOrder

        XCTAssertThrowsError(
            try repository.applyOrderAssignments([
                ItemOrderAssignment(id: item.id, isPinned: true, sortOrder: 9),
                ItemOrderAssignment(id: UUID(), isPinned: false, sortOrder: 0),
            ])
        )

        XCTAssertFalse(item.isPinned)
        XCTAssertEqual(item.sortOrder, originalRank)
    }

    func testLegacySortOrderBackfillIsDeterministicAndIdempotent() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let older = CaptureItem(
            text: "Older",
            origin: .manual,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = CaptureItem(
            text: "Newer",
            origin: .manual,
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        container.mainContext.insert(older)
        container.mainContext.insert(newer)
        try container.mainContext.save()

        XCTAssertTrue(try repository.backfillMissingSortOrders())
        XCTAssertEqual(newer.sortOrder, 0)
        XCTAssertEqual(older.sortOrder, 1)
        XCTAssertFalse(try repository.backfillMissingSortOrders())
        XCTAssertEqual(try repository.fetch(scope: .inbox).map(\.id), [newer.id, older.id])
    }

    func testArchiveAndRestorePreserveManualRank() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let item = try repository.createItem(text: "Keep my place", origin: .manual)
        let rank = item.sortOrder

        try repository.archive(item)
        try repository.restore(item)

        XCTAssertEqual(item.sortOrder, rank)
    }

    func testLegacyPackageWithoutSortOrderImportsAndBackfills() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        let sourceContainer = try makeContainer()
        let sourceStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("source-store", isDirectory: true))
        let sourceRepository = ItemRepository(modelContext: sourceContainer.mainContext)
        let older = try sourceRepository.createItem(
            text: "Older",
            origin: .manual,
            now: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = try sourceRepository.createItem(
            text: "Newer",
            origin: .manual,
            now: Date(timeIntervalSinceReferenceDate: 200)
        )
        let package = temporary.appendingPathComponent("Legacy.notchcapture", isDirectory: true)
        try CapturePackageService(modelContext: sourceContainer.mainContext, attachmentStore: sourceStore).export(to: package)

        let manifestURL = package.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var records = try XCTUnwrap(manifest["items"] as? [[String: Any]])
        for index in records.indices {
            records[index].removeValue(forKey: "sortOrder")
        }
        manifest["items"] = records
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL, options: .atomic)

        let targetContainer = try makeContainer()
        let targetStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("target-store", isDirectory: true))
        _ = try CapturePackageService(modelContext: targetContainer.mainContext, attachmentStore: targetStore)
            .importPackage(at: package)
        let targetRepository = ItemRepository(modelContext: targetContainer.mainContext)
        XCTAssertTrue(try targetRepository.backfillMissingSortOrders())
        XCTAssertEqual(try targetRepository.fetch(scope: .inbox).map(\.id), [newer.id, older.id])
    }

    func testPackageRoundTripAndDuplicateSkip() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        let sourceContainer = try makeContainer()
        let sourceStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("source-store", isDirectory: true))
        let stored = try sourceStore.storeData(
            Data("image bytes".utf8),
            filename: "capture.png",
            type: .png,
            kind: .image
        )
        let attachment = Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath
        )
        let list = ItemList(name: "Research", sortOrder: 0)
        sourceContainer.mainContext.insert(list)
        let repository = ItemRepository(modelContext: sourceContainer.mainContext)
        let original = try repository.createItem(
            text: "Saved selection",
            origin: .selection,
            source: CaptureSource(applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
            attachments: [attachment]
        )
        try repository.move(original, to: list)
        let completedAt = Date(timeIntervalSince1970: 1_700_200_000)
        try repository.setKind(.task, for: original)
        try repository.setCompleted(true, for: original, at: completedAt)

        let package = temporary.appendingPathComponent("Export.notchcapture", isDirectory: true)
        let exporter = CapturePackageService(modelContext: sourceContainer.mainContext, attachmentStore: sourceStore)
        try exporter.export(to: package)

        let targetContainer = try makeContainer()
        let targetStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("target-store", isDirectory: true))
        let importer = CapturePackageService(modelContext: targetContainer.mainContext, attachmentStore: targetStore)
        let first = try importer.importPackage(at: package)
        XCTAssertEqual(first.importedItemCount, 1)
        XCTAssertEqual(first.skippedDuplicateCount, 0)

        let imported = try targetContainer.mainContext.fetch(FetchDescriptor<CaptureItem>())
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].id, original.id)
        XCTAssertEqual(imported[0].text, original.text)
        XCTAssertEqual(imported[0].origin, .selection)
        XCTAssertEqual(imported[0].list?.name, "Research")
        XCTAssertEqual(imported[0].completedAt, completedAt)
        XCTAssertEqual(imported[0].sortOrder, original.sortOrder)
        XCTAssertEqual(imported[0].attachments.count, 1)
        let importedPath = try XCTUnwrap(imported[0].attachments[0].relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try targetStore.resolve(relativePath: importedPath).path))

        let second = try importer.importPackage(at: package)
        XCTAssertEqual(second.importedItemCount, 0)
        XCTAssertEqual(second.skippedDuplicateCount, 1)
    }

    func testPackageRoundTripPreservesCachedURLFavicon() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        let sourceContainer = try makeContainer()
        let sourceStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("source", isDirectory: true))
        let favicon = try sourceStore.storeData(
            Data("favicon bytes".utf8),
            filename: "Favicon.png",
            type: .png,
            kind: .image
        )
        let attachment = Attachment(
            kind: .url,
            typeIdentifier: UTType.url.identifier,
            originalFilename: "example.com",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            faviconRelativePath: favicon.relativePath,
            faviconTypeIdentifier: favicon.typeIdentifier
        )
        _ = try ItemRepository(modelContext: sourceContainer.mainContext).createItem(
            origin: .manual,
            attachments: [attachment]
        )

        let package = temporary.appendingPathComponent("Favicon.notchcapture", isDirectory: true)
        try CapturePackageService(modelContext: sourceContainer.mainContext, attachmentStore: sourceStore)
            .export(to: package)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any]
        )
        XCTAssertEqual(manifest["schemaVersion"] as? Int, 3)

        let targetContainer = try makeContainer()
        let targetStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("target", isDirectory: true))
        _ = try CapturePackageService(modelContext: targetContainer.mainContext, attachmentStore: targetStore)
            .importPackage(at: package)
        let importedAttachment = try XCTUnwrap(
            targetContainer.mainContext.fetch(FetchDescriptor<CaptureItem>()).first?.attachments.first
        )
        let importedFaviconPath = try XCTUnwrap(importedAttachment.faviconRelativePath)
        XCTAssertEqual(importedAttachment.faviconTypeIdentifier, UTType.png.identifier)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try targetStore.resolve(relativePath: importedFaviconPath).path))
    }

    func testPackageRoundTripIncludesSharedAndStandaloneTags() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        let sourceContainer = try makeContainer()
        let sourceStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("source", isDirectory: true))
        let sourceRepository = ItemRepository(modelContext: sourceContainer.mainContext)
        let original = try sourceRepository.createItem(
            text: "Tagged thought for @Lipe",
            origin: .manual,
            tagNames: ["Lipe"]
        )
        _ = try sourceRepository.createTag(name: "Standalone")

        let package = temporary.appendingPathComponent("Tags.notchcapture", isDirectory: true)
        try CapturePackageService(modelContext: sourceContainer.mainContext, attachmentStore: sourceStore)
            .export(to: package)

        let targetContainer = try makeContainer()
        let targetStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("target", isDirectory: true))
        let importer = CapturePackageService(modelContext: targetContainer.mainContext, attachmentStore: targetStore)
        let result = try importer.importPackage(at: package)

        XCTAssertEqual(result.importedItemCount, 1)
        let imported = try XCTUnwrap(
            targetContainer.mainContext.fetch(FetchDescriptor<CaptureItem>()).first { $0.id == original.id }
        )
        XCTAssertEqual(imported.text, "Tagged thought for @Lipe")
        XCTAssertEqual(imported.tags.map(\.name), ["Lipe"])
        XCTAssertEqual(imported.tags.first?.colorSeed, original.tags.first?.colorSeed)
        XCTAssertEqual(
            Set(try targetContainer.mainContext.fetch(FetchDescriptor<CaptureTag>()).map(\.name)),
            Set(["Lipe", "Standalone"])
        )
        XCTAssertEqual(try importer.importPackage(at: package).skippedDuplicateCount, 1)
    }

    func testVersionOnePackageImportsWithoutTags() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        let sourceContainer = try makeContainer()
        let sourceStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("source", isDirectory: true))
        let repository = ItemRepository(modelContext: sourceContainer.mainContext)
        _ = try repository.createItem(text: "Legacy", origin: .manual, tagNames: ["Ignored"])
        let package = temporary.appendingPathComponent("Legacy-v1.notchcapture", isDirectory: true)
        try CapturePackageService(modelContext: sourceContainer.mainContext, attachmentStore: sourceStore)
            .export(to: package)

        let manifestURL = package.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifest["schemaVersion"] = 1
        manifest.removeValue(forKey: "tags")
        var records = try XCTUnwrap(manifest["items"] as? [[String: Any]])
        for index in records.indices { records[index].removeValue(forKey: "tagIDs") }
        manifest["items"] = records
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL, options: .atomic)

        let targetContainer = try makeContainer()
        let targetStore = try AttachmentStore(rootURL: temporary.appendingPathComponent("target", isDirectory: true))
        _ = try CapturePackageService(modelContext: targetContainer.mainContext, attachmentStore: targetStore)
            .importPackage(at: package)

        XCTAssertTrue(try targetContainer.mainContext.fetch(FetchDescriptor<CaptureTag>()).isEmpty)
        XCTAssertTrue(try XCTUnwrap(
            targetContainer.mainContext.fetch(FetchDescriptor<CaptureItem>()).first
        ).tags.isEmpty)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CaptureItem.self, CaptureTag.self, ItemList.self, Attachment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
