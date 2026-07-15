import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import NotchCapture

@MainActor
final class CaptureDataTests: XCTestCase {
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

        try repository.setCompleted(true, for: note)
        XCTAssertTrue(try repository.fetch(scope: .inbox).isEmpty)
        XCTAssertEqual(try repository.fetch(scope: .completed).map(\.id), [note.id])

        try repository.trash(note)
        XCTAssertEqual(try repository.fetch(scope: .trash).map(\.id), [note.id])
        try repository.restore(note)
        XCTAssertEqual(try repository.fetch(scope: .completed).map(\.id), [note.id])
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

    func testAttachmentStoreRejectsTraversal() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try AttachmentStore(rootURL: temporary)
        XCTAssertThrowsError(try store.resolve(relativePath: "../outside"))
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
        XCTAssertEqual(imported[0].attachments.count, 1)
        let importedPath = try XCTUnwrap(imported[0].attachments[0].relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try targetStore.resolve(relativePath: importedPath).path))

        let second = try importer.importPackage(at: package)
        XCTAssertEqual(second.importedItemCount, 0)
        XCTAssertEqual(second.skippedDuplicateCount, 1)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CaptureItem.self, ItemList.self, Attachment.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
