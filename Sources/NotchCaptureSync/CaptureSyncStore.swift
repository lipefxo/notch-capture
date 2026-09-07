import Foundation

public enum CaptureSyncError: LocalizedError, Sendable, Equatable {
    case cloudKitRequiresSignedDevice

    public var errorDescription: String? {
        switch self {
        case .cloudKitRequiresSignedDevice:
            "iCloud sync requires a signed device build. Local captures remain available."
        }
    }
}

public actor CaptureSyncStore {
    private let cache: JSONSyncCache
    private let containerIdentifier: String
    private let cloudKitEnabled: Bool
    private var cloud: CloudKitPrivateDatabaseClient?
    private var cachedRecords: [CaptureRecord]
    private var outbox: [SyncMutation]

    public init(
        containerIdentifier: String,
        cacheURL: URL? = nil,
        cloudKitEnabled: Bool = true
    ) {
        let resolvedURL = cacheURL ?? Self.defaultCacheURL()
        let cache = JSONSyncCache(cacheURL: resolvedURL)
        self.cache = cache
        self.containerIdentifier = containerIdentifier
        self.cloudKitEnabled = cloudKitEnabled
        self.cloud = nil
        let loadedRecords = (try? cache.loadRecords()) ?? []
        let loadedOutbox = Self.migratingLegacyDeletes(
            (try? cache.loadOutbox()) ?? [],
            records: loadedRecords
        )
        self.outbox = loadedOutbox
        self.cachedRecords = Self.applying(
            loadedOutbox,
            to: loadedRecords
        )
    }

    public func records(includingDeleted: Bool = false) -> [CaptureRecord] {
        includingDeleted ? cachedRecords : cachedRecords.filter { $0.deletedAt == nil }
    }

    /// Persists immediately to the local cache. Cloud delivery is deliberately
    /// deferred to `synchronize()` so offline capture is fast and reliable.
    public func upsert(_ record: CaptureRecord) throws {
        cachedRecords = CaptureRecordMerger.merge(local: cachedRecords, remote: [record])
        let accepted = cachedRecords.first { $0.id == record.id } ?? record
        outbox.removeAll { $0.id == record.id }
        outbox.append(.upsert(accepted))
        try persist()
    }

    /// Hides immediately and queues a permanent tombstone. Retaining the record
    /// prevents an offline device from recreating a capture after reconnecting.
    public func delete(id: UUID, at date: Date = .now) throws {
        let existing = cachedRecords.first { $0.id == id }
        let tombstone = Self.tombstone(for: existing, id: id, at: date)
        cachedRecords.removeAll { $0.id == id }
        cachedRecords.append(tombstone)
        cachedRecords.sort { $0.id.uuidString < $1.id.uuidString }
        outbox.removeAll { $0.id == id }
        outbox.append(.upsert(tombstone))
        try persist()
    }

    /// Flushes local mutations, then incorporates private-database records.
    /// If CloudKit fails, the unacknowledged mutation remains in the outbox.
    @discardableResult
    public func synchronize(includingDeleted: Bool = false) async throws -> [CaptureRecord] {
        guard cloudKitEnabled else {
            throw CaptureSyncError.cloudKitRequiresSignedDevice
        }
#if targetEnvironment(simulator)
        // CKContainer traps instead of throwing when a Simulator app lacks a
        // provisioned iCloud entitlement. Keep previews safely offline; signed
        // device builds use the CloudKit path below.
        throw CaptureSyncError.cloudKitRequiresSignedDevice
#else
        let cloud: CloudKitPrivateDatabaseClient
        if let existingClient = self.cloud {
            cloud = existingClient
        } else {
            let newClient = CloudKitPrivateDatabaseClient(containerIdentifier: containerIdentifier)
            self.cloud = newClient
            cloud = newClient
        }

        while let mutation = outbox.first {
            switch mutation {
            case let .upsert(record):
                let accepted = try await cloud.save(record)
                cachedRecords = CaptureRecordMerger.merge(
                    local: cachedRecords,
                    remote: [accepted]
                )
            case let .delete(id, deletedAt):
                if let newerRemote = try await cloud.delete(
                    id: id,
                    unlessUpdatedAfter: deletedAt
                ) {
                    cachedRecords = CaptureRecordMerger.merge(
                        local: cachedRecords,
                        remote: [newerRemote]
                    )
                }
            }
            outbox.removeFirst()
            try persist()
        }

        let remote = try await cloud.fetchAll()
        cachedRecords = CaptureRecordMerger.merge(local: cachedRecords, remote: remote)
        try cache.saveRecords(cachedRecords)
        return includingDeleted ? cachedRecords : cachedRecords.filter { $0.deletedAt == nil }
#endif
    }

    private func persist() throws {
        // Save the mutation first: a crash between these writes may briefly show
        // stale UI, but cannot silently lose a cloud-bound change.
        try cache.saveOutbox(outbox)
        try cache.saveRecords(cachedRecords)
    }

    private nonisolated static func defaultCacheURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("NotchCapture", isDirectory: true)
            .appendingPathComponent("sync-cache.json")
    }

    /// The outbox is written before the snapshot. Replaying it at launch closes
    /// the small crash window between those two atomic file writes.
    private nonisolated static func applying(
        _ mutations: [SyncMutation],
        to records: [CaptureRecord]
    ) -> [CaptureRecord] {
        var result = records
        for mutation in mutations {
            switch mutation {
            case let .upsert(record):
                result = CaptureRecordMerger.merge(local: result, remote: [record])
            case let .delete(id, _):
                result.removeAll { $0.id == id }
            }
        }
        return result
    }

    private nonisolated static func migratingLegacyDeletes(
        _ mutations: [SyncMutation],
        records: [CaptureRecord]
    ) -> [SyncMutation] {
        mutations.map { mutation in
            guard case let .delete(id, deletedAt) = mutation else { return mutation }
            return .upsert(tombstone(
                for: records.first { $0.id == id },
                id: id,
                at: deletedAt
            ))
        }
    }

    private nonisolated static func tombstone(
        for existing: CaptureRecord?,
        id: UUID,
        at date: Date
    ) -> CaptureRecord {
        var record = existing ?? CaptureRecord(
            id: id,
            text: "",
            createdAt: date,
            updatedAt: date
        )
        record.text = ""
        record.kind = .note
        record.isCompleted = false
        record.completedAt = nil
        record.dueDate = nil
        record.isPinned = false
        record.archivedAt = nil
        record.trashedAt = nil
        record.folderID = nil
        record.folderName = nil
        record.tags = []
        record.deletedAt = date
        record.markChanged(Set(CaptureField.allCases), at: date)
        return record
    }
}
