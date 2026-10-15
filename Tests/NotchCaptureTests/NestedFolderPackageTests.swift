import Foundation
import SwiftData
import XCTest
@testable import NotchCapture

@MainActor
final class NestedFolderPackageTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema(NotchCaptureSchemaV3.models)
        return try ModelContainer(for: schema, migrationPlan: NotchCaptureMigrationPlan.self,
                                  configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func service(_ store: ModelContainer, at url: URL) throws -> CapturePackageService {
        try CapturePackageService(modelContext: store.mainContext, attachmentStore: AttachmentStore(rootURL: url))
    }

    private func changeManifest(at package: URL, _ transform: (inout [String: Any]) -> Void) throws {
        let url = package.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        transform(&manifest)
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
    }

    func testRoundTripPreservesDeepAndEmptyFoldersAndRepeatedImportSkipsItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try container()
        let repository = ItemRepository(modelContext: source.mainContext)
        let root = try repository.createList(name: "Work")
        let child = try repository.createList(name: "Research", parentID: root.id)
        let deep = try repository.createList(name: "Drafts", parentID: child.id)
        let empty = try repository.createList(name: "Empty", parentID: deep.id)
        let item = try repository.createItem(text: "Keep", origin: .manual, list: deep)
        let package = directory.appendingPathComponent("export.notchcapture")
        try service(source, at: directory.appendingPathComponent("source")).export(to: package)
        try changeManifest(at: package) { manifest in
            // Children need not follow their parents in a manifest.
            manifest["lists"] = (manifest["lists"] as? [[String: Any]])?.reversed().map { $0 }
            XCTAssertEqual(manifest["schemaVersion"] as? Int, 7)
        }
        let target = try container()
        let importer = try service(target, at: directory.appendingPathComponent("target"))
        XCTAssertEqual(try importer.importPackage(at: package).importedItemCount, 1)
        let folders = try target.mainContext.fetch(FetchDescriptor<ItemList>())
        XCTAssertEqual(folders.count, 4)
        XCTAssertEqual(folders.first { $0.id == child.id }?.parentID, root.id)
        XCTAssertEqual(folders.first { $0.id == deep.id }?.parentID, child.id)
        XCTAssertEqual(folders.first { $0.id == empty.id }?.parentID, deep.id)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<CaptureItem>()).first?.id, item.id)
        let repeated = try importer.importPackage(at: package)
        XCTAssertEqual(repeated.importedItemCount, 0)
        XCTAssertEqual(repeated.skippedDuplicateCount, 1)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<ItemList>()).count, 4)
    }

    func testConflictingParentIDsAreRemappedThroughTheWholeTree() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try container()
        let repository = ItemRepository(modelContext: source.mainContext)
        let root = try repository.createList(name: "Imported")
        let child = try repository.createList(name: "Research", parentID: root.id)
        let deep = try repository.createList(name: "Drafts", parentID: child.id)
        let item = try repository.createItem(text: "Imported capture", origin: .manual, list: deep)
        let package = directory.appendingPathComponent("export.notchcapture")
        try service(source, at: directory.appendingPathComponent("source")).export(to: package)
        let target = try container()
        let local = ItemList(id: root.id, name: "Local")
        let localChild = ItemList(id: child.id, name: "Research", parentID: local.id)
        target.mainContext.insert(local)
        target.mainContext.insert(localChild)
        try target.mainContext.save()
        let importer = try service(target, at: directory.appendingPathComponent("target"))
        let imported = try importer.importPackage(at: package)
        XCTAssertEqual(imported.reassignedIdentifierCount, 2)
        let folders = try target.mainContext.fetch(FetchDescriptor<ItemList>())
        let importedRoot = try XCTUnwrap(folders.first { $0.name == "Imported" })
        let importedChild = try XCTUnwrap(folders.first { $0.parentID == importedRoot.id })
        XCTAssertNotEqual(importedRoot.id, root.id)
        XCTAssertNotEqual(importedChild.id, child.id)
        XCTAssertEqual(folders.first { $0.id == deep.id }?.parentID, importedChild.id)
        XCTAssertEqual(localChild.parentID, local.id)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<CaptureItem>()).first?.id, item.id)
        XCTAssertEqual(try importer.importPackage(at: package).skippedDuplicateCount, 1)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<ItemList>()).count, 5)
    }

    func testLegacyPackagesIgnoreParentFieldsAndImportFoldersAtRoot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try container()
        let repository = ItemRepository(modelContext: source.mainContext)
        let root = try repository.createList(name: "Work")
        _ = try repository.createList(name: "Research", parentID: root.id)
        let package = directory.appendingPathComponent("legacy.notchcapture")
        try service(source, at: directory.appendingPathComponent("source")).export(to: package)
        for version in 1...6 {
            try changeManifest(at: package) { $0["schemaVersion"] = version }
            let target = try container()
            _ = try service(target, at: directory.appendingPathComponent("target-\(version)")).importPackage(at: package)
            XCTAssertTrue(try target.mainContext.fetch(FetchDescriptor<ItemList>()).allSatisfy { $0.parentID == nil })
        }
    }

    func testInvalidFolderGraphsAreRejectedBeforeChangingTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try container()
        let repository = ItemRepository(modelContext: source.mainContext)
        let root = try repository.createList(name: "Work")
        let child = try repository.createList(name: "Research", parentID: root.id)
        let package = directory.appendingPathComponent("invalid.notchcapture")
        try service(source, at: directory.appendingPathComponent("source")).export(to: package)
        let original = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let target = try container()
        let kept = try ItemRepository(modelContext: target.mainContext).createList(name: "Keep")
        let importer = try service(target, at: directory.appendingPathComponent("target"))
        for mutation in ["missing", "self", "cycle", "duplicate"] {
            try original.write(to: package.appendingPathComponent("manifest.json"))
            try changeManifest(at: package) { manifest in
                var lists = manifest["lists"] as! [[String: Any]]
                let rootIndex = lists.firstIndex { $0["id"] as? String == root.id.uuidString }!
                switch mutation {
                case "missing": lists[rootIndex]["parentID"] = UUID().uuidString
                case "self": lists[rootIndex]["parentID"] = root.id.uuidString
                case "cycle": lists[rootIndex]["parentID"] = child.id.uuidString
                default: lists.append(lists[rootIndex])
                }
                manifest["lists"] = lists
            }
            XCTAssertThrowsError(try importer.importPackage(at: package), mutation)
            XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<ItemList>()).map(\.id), [kept.id])
            XCTAssertFalse(target.mainContext.hasChanges)
        }
    }
}
