import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import NotchCapture

private enum RecoverySaveFailure: Error {
    case injected
}

@MainActor
final class RecoveryPersistenceTests: XCTestCase {
    func testArchiveSaveFailureRollsBackStatusAndTimestamp() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let baseline = Date(timeIntervalSinceReferenceDate: 100)
        let item = try repository.createItem(
            text: "Keep this capture",
            origin: .manual,
            now: baseline
        )
        let failingRepository = makeFailingRepository(for: container.mainContext)

        XCTAssertThrowsError(
            try failingRepository.archive(item, at: baseline.addingTimeInterval(10))
        )

        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertNil(item.archivedAt)
        XCTAssertNil(item.trashedAt)
        XCTAssertEqual(item.updatedAt, baseline)
        try container.mainContext.save()

        let persisted = try persistedItem(item.id, in: container)
        XCTAssertNil(persisted.archivedAt)
        XCTAssertNil(persisted.trashedAt)
        XCTAssertEqual(persisted.updatedAt, baseline)
    }

    func testTrashSaveFailureRollsBackStatusAndTimestamp() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let baseline = Date(timeIntervalSinceReferenceDate: 200)
        let item = try repository.createItem(
            text: "Keep this capture",
            origin: .manual,
            now: baseline
        )
        let failingRepository = makeFailingRepository(for: container.mainContext)

        XCTAssertThrowsError(
            try failingRepository.trash(item, at: baseline.addingTimeInterval(10))
        )

        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertNil(item.archivedAt)
        XCTAssertNil(item.trashedAt)
        XCTAssertEqual(item.updatedAt, baseline)
        try container.mainContext.save()

        let persisted = try persistedItem(item.id, in: container)
        XCTAssertNil(persisted.archivedAt)
        XCTAssertNil(persisted.trashedAt)
        XCTAssertEqual(persisted.updatedAt, baseline)
    }

    func testTrashCompletedTasksSaveFailureRollsBackEveryManagedRow() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let firstCompletedAt = Date(timeIntervalSinceReferenceDate: 250)
        let secondCompletedAt = Date(timeIntervalSinceReferenceDate: 260)
        let first = try repository.createItem(text: "First completed task", origin: .manual)
        let second = try repository.createItem(text: "Second completed task", origin: .manual)
        try repository.setKind(.task, for: first)
        try repository.setKind(.task, for: second)
        try repository.setCompleted(true, for: first, at: firstCompletedAt)
        try repository.setCompleted(true, for: second, at: secondCompletedAt)
        let failingRepository = makeFailingRepository(for: container.mainContext)

        XCTAssertThrowsError(
            try failingRepository.trashCompletedTasks(at: Date(timeIntervalSinceReferenceDate: 270))
        )

        XCTAssertFalse(container.mainContext.hasChanges)
        for item in [first, second] {
            XCTAssertTrue(item.isCompleted)
            XCTAssertNil(item.trashedAt)
        }
        XCTAssertEqual(first.updatedAt, firstCompletedAt)
        XCTAssertEqual(second.updatedAt, secondCompletedAt)
        try container.mainContext.save()

        let persistedFirst = try persistedItem(first.id, in: container)
        let persistedSecond = try persistedItem(second.id, in: container)
        XCTAssertTrue(persistedFirst.isCompleted)
        XCTAssertTrue(persistedSecond.isCompleted)
        XCTAssertNil(persistedFirst.trashedAt)
        XCTAssertNil(persistedSecond.trashedAt)
        XCTAssertEqual(persistedFirst.updatedAt, firstCompletedAt)
        XCTAssertEqual(persistedSecond.updatedAt, secondCompletedAt)
    }

    func testRestoreSaveFailureRollsBackStatusAndCompletionTogether() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let createdAt = Date(timeIntervalSinceReferenceDate: 300)
        let completedAt = Date(timeIntervalSinceReferenceDate: 310)
        let archivedAt = Date(timeIntervalSinceReferenceDate: 320)
        let item = try repository.createItem(
            text: "Keep this completed task",
            origin: .manual,
            now: createdAt
        )
        try repository.setKind(.task, for: item)
        try repository.setCompleted(true, for: item, at: completedAt)
        try repository.archive(item, at: archivedAt)
        let failingRepository = makeFailingRepository(for: container.mainContext)

        XCTAssertThrowsError(try failingRepository.restore(item, markIncomplete: true))

        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertEqual(item.kind, .task)
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.completedAt, completedAt)
        XCTAssertEqual(item.archivedAt, archivedAt)
        XCTAssertNil(item.trashedAt)
        try container.mainContext.save()

        let persisted = try persistedItem(item.id, in: container)
        XCTAssertEqual(persisted.kind, .task)
        XCTAssertTrue(persisted.isCompleted)
        XCTAssertEqual(persisted.completedAt, completedAt)
        XCTAssertEqual(persisted.archivedAt, archivedAt)
        XCTAssertNil(persisted.trashedAt)
    }

    func testRestoreCanClearStatusAndCompletionAtomically() throws {
        let container = try makeContainer()
        let repository = ItemRepository(modelContext: container.mainContext)
        let item = try repository.createItem(text: "Finish later", origin: .manual)
        try repository.setKind(.task, for: item)
        try repository.setCompleted(true, for: item, at: Date(timeIntervalSinceReferenceDate: 410))
        try repository.archive(item, at: Date(timeIntervalSinceReferenceDate: 420))

        try repository.restore(item, markIncomplete: true)

        let persisted = try persistedItem(item.id, in: container)
        XCTAssertEqual(persisted.kind, .task)
        XCTAssertFalse(persisted.isCompleted)
        XCTAssertNil(persisted.completedAt)
        XCTAssertNil(persisted.archivedAt)
        XCTAssertNil(persisted.trashedAt)
    }

    func testPermanentDeleteSaveFailureKeepsItemAndStoredAttachments() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = try AttachmentStore(rootURL: temporary)
        let container = try makeContainer()
        let repository = ItemRepository(
            modelContext: container.mainContext,
            attachmentStore: store
        )
        let item = try repository.createItem(
            from: .image(Data("pixels".utf8), typeIdentifier: UTType.png.identifier),
            origin: .manual
        )
        let relativePath = try XCTUnwrap(item.attachments.first?.relativePath)
        let fileURL = try store.resolve(relativePath: relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let failingRepository = makeFailingRepository(
            for: container.mainContext,
            attachmentStore: store
        )

        XCTAssertThrowsError(try failingRepository.deletePermanently(item))

        XCTAssertFalse(container.mainContext.hasChanges)
        XCTAssertFalse(item.isTrashed)
        XCTAssertFalse(item.isArchived)
        XCTAssertEqual(item.attachments.count, 1)
        XCTAssertEqual(item.attachments.first?.relativePath, relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        try container.mainContext.save()

        let persisted = try persistedItem(item.id, in: container)
        XCTAssertEqual(persisted.attachments.count, 1)
        XCTAssertEqual(persisted.attachments.first?.relativePath, relativePath)
        XCTAssertFalse(persisted.isTrashed)
        XCTAssertFalse(persisted.isArchived)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeFailingRepository(
        for context: ModelContext,
        attachmentStore: AttachmentStore? = nil
    ) -> ItemRepository {
        ItemRepository(
            modelContext: context,
            attachmentStore: attachmentStore,
            saveHandler: { throw RecoverySaveFailure.injected }
        )
    }

    private func persistedItem(_ id: UUID, in container: ModelContainer) throws -> CaptureItem {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CaptureItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try XCTUnwrap(context.fetch(descriptor).first)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(NotchCaptureSchemaV2.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: NotchCaptureMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
