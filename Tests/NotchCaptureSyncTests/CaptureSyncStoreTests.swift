import Foundation
import Testing
@testable import NotchCaptureSync

struct CaptureSyncStoreTests {
    @Test func disabledCloudKitFailsWithoutCreatingAClient() async {
        let store = CaptureSyncStore(
            containerIdentifier: "iCloud.com.example.NotchCaptureTests",
            cloudKitEnabled: false
        )

        await #expect(throws: CaptureSyncError.cloudKitRequiresSignedDevice) {
            try await store.synchronize()
        }
    }

    @Test func localCacheAndOutboxRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("captures.json")
        let container = "iCloud.com.example.NotchCaptureTests"
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.125)
        let record = CaptureRecord(
            text: "A note from the phone",
            folderName: "Inbox",
            tags: ["mobile"],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let firstStore = CaptureSyncStore(containerIdentifier: container, cacheURL: cacheURL)
        try await firstStore.upsert(record)
        #expect(await firstStore.records() == [record])

        let restoredStore = CaptureSyncStore(containerIdentifier: container, cacheURL: cacheURL)
        #expect(await restoredStore.records() == [record])

        let cache = JSONSyncCache(cacheURL: cacheURL)
        #expect(try cache.loadRecords() == [record])
        #expect(try cache.loadOutbox() == [.upsert(record)])
    }

    @Test func deletionPersistsAsHiddenTombstone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("captures.json")
        let container = "iCloud.com.example.NotchCaptureTests"
        let record = CaptureRecord(text: "Remove everywhere")
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let store = CaptureSyncStore(containerIdentifier: container, cacheURL: cacheURL)
        try await store.upsert(record)
        try await store.delete(id: record.id, at: deletedAt)

        #expect(await store.records().isEmpty)
        let tombstones = await store.records(includingDeleted: true)
        #expect(tombstones.count == 1)
        #expect(tombstones.first?.deletedAt == deletedAt)
        #expect(tombstones.first?.text.isEmpty == true)

        let restored = CaptureSyncStore(containerIdentifier: container, cacheURL: cacheURL)
        #expect(await restored.records().isEmpty)
        #expect(await restored.records(includingDeleted: true).first?.deletedAt == deletedAt)
    }
}
