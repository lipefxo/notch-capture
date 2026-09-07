import Foundation
import NotchCaptureSync
import Security
import SwiftData

/// Mirrors the local SwiftData ledger into the small, platform-neutral records
/// consumed by the iPhone and Apple Watch companions. The local database stays
/// authoritative for attachments; companion sync intentionally carries only
/// capture metadata so a mobile edit can never orphan a Mac attachment file.
@MainActor
final class CompanionSyncService {
    private static let containerIdentifier = "iCloud.com.lipe.notchcapture"
    private static let knownIDsDefaultsKey = "companionSync.knownLocalItemIDs"

    private static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-services" as CFString,
            nil
        )
        return entitlement != nil
    }

    private let modelContext: ModelContext
    private let store: CaptureSyncStore
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?
    private var onImportedChanges: (() -> Void)?
    private var hasKnownLocalSnapshot: Bool
    private var knownLocalIDs: Set<UUID>

    init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        resetDeletionBaseline: Bool = false
    ) {
        self.modelContext = modelContext
        self.store = CaptureSyncStore(
            containerIdentifier: Self.containerIdentifier,
            cloudKitEnabled: Self.hasCloudKitEntitlement
        )
        self.defaults = defaults
        if resetDeletionBaseline {
            defaults.removeObject(forKey: Self.knownIDsDefaultsKey)
            self.hasKnownLocalSnapshot = false
            self.knownLocalIDs = []
        } else {
            self.hasKnownLocalSnapshot = defaults.object(forKey: Self.knownIDsDefaultsKey) != nil
            self.knownLocalIDs = Set(
                (defaults.stringArray(forKey: Self.knownIDsDefaultsKey) ?? [])
                    .compactMap(UUID.init(uuidString:))
            )
        }
    }

    func start(onImportedChanges: @escaping () -> Void) {
        guard syncTask == nil else { return }
        self.onImportedChanges = onImportedChanges
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        syncTask = nil
        onImportedChanges = nil
    }

    func synchronize() async {
        do {
            let localItems = try modelContext.fetch(FetchDescriptor<CaptureItem>())
            let localIDs = Set(localItems.map(\.id))
            if hasKnownLocalSnapshot {
                for deletedID in knownLocalIDs.subtracting(localIDs) {
                    try await store.delete(id: deletedID)
                }
            } else {
                hasKnownLocalSnapshot = true
            }
            persistKnownLocalIDs(localIDs)

            let cachedByID = Dictionary(uniqueKeysWithValues: await store.records(
                includingDeleted: true
            ).map { ($0.id, $0) })

            for item in localItems {
                // A tombstone may have reached the cache immediately before a
                // crash. Never export that still-present SwiftData row again;
                // applying the cached tombstone below will finish the deletion.
                if cachedByID[item.id]?.deletedAt != nil { continue }
                let record = Self.record(from: item, previous: cachedByID[item.id])
                if let cached = cachedByID[record.id], cached == record { continue }
                try await store.upsert(record)
            }

            let merged = try await store.synchronize(includingDeleted: true)
            if try apply(records: merged, to: localItems) {
                onImportedChanges?()
            }
            let finalIDs = try Set(modelContext.fetch(FetchDescriptor<CaptureItem>()).map(\.id))
            persistKnownLocalIDs(finalIDs)
        } catch {
            // The sync cache and outbox are deliberately offline-first. Missing
            // entitlements, no account, and ordinary network errors are retried
            // without disturbing the local capture experience.
        }
    }

    private func persistKnownLocalIDs(_ ids: Set<UUID>) {
        knownLocalIDs = ids
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.knownIDsDefaultsKey)
    }

    private func apply(records: [CaptureRecord], to localItems: [CaptureItem]) throws -> Bool {
        var changed = false
        var itemsByID = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })
        var lists = try modelContext.fetch(FetchDescriptor<ItemList>())
        var tags = try modelContext.fetch(FetchDescriptor<CaptureTag>())

        for record in records {
            if record.deletedAt != nil {
                if let item = itemsByID.removeValue(forKey: record.id) {
                    modelContext.delete(item)
                    changed = true
                }
                continue
            }
            if let item = itemsByID[record.id] {
                guard !Self.hasSameValues(record, as: item) else { continue }
                let resolvedList = resolveList(for: record, in: &lists)
                let resolvedTags = resolveTags(named: record.tags, in: &tags, now: record.updatedAt)
                item.text = record.text
                item.kindRawValue = Self.localKind(record.kind).rawValue
                item.isCompleted = record.kind == .task && record.isCompleted
                item.completedAt = item.isCompleted ? record.completedAt : nil
                item.dueDate = record.dueDate
                item.isPinned = record.isPinned
                item.archivedAt = record.archivedAt
                item.trashedAt = record.trashedAt
                item.list = resolvedList
                item.tags = resolvedTags
                item.updatedAt = record.updatedAt
                changed = true
                continue
            }

            let resolvedList = resolveList(for: record, in: &lists)
            let resolvedTags = resolveTags(named: record.tags, in: &tags, now: record.updatedAt)
            let item = CaptureItem(
                id: record.id,
                text: record.text,
                kind: Self.localKind(record.kind),
                isCompleted: record.kind == .task && record.isCompleted,
                completedAt: record.kind == .task && record.isCompleted ? record.completedAt : nil,
                dueDate: record.dueDate,
                isPinned: record.isPinned,
                archivedAt: record.archivedAt,
                trashedAt: record.trashedAt,
                sortOrder: nextSortOrder(
                    isPinned: record.isPinned,
                    listID: resolvedList?.id,
                    items: Array(itemsByID.values)
                ),
                origin: .imported,
                list: resolvedList,
                tags: resolvedTags,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            modelContext.insert(item)
            itemsByID[item.id] = item
            changed = true
        }

        if changed { try modelContext.save() }
        return changed
    }

    private func nextSortOrder(
        isPinned: Bool,
        listID: UUID?,
        items: [CaptureItem]
    ) -> Int {
        let ranks = items.compactMap { item -> Int? in
            guard item.isPinned == isPinned, item.list?.id == listID else { return nil }
            return item.sortOrder
        }
        return (ranks.max() ?? -1) + 1
    }

    private func resolveList(for record: CaptureRecord, in lists: inout [ItemList]) -> ItemList? {
        guard let name = record.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        if let id = record.folderID, let existing = lists.first(where: { $0.id == id }) {
            return existing
        }
        if let existing = lists.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        let list = ItemList(
            id: record.folderID ?? UUID(),
            name: name,
            sortOrder: (lists.map(\.sortOrder).max() ?? -1) + 1,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
        modelContext.insert(list)
        lists.append(list)
        return list
    }

    private func resolveTags(
        named names: [String],
        in tags: inout [CaptureTag],
        now: Date
    ) -> [CaptureTag] {
        var resolved: [CaptureTag] = []
        for proposedName in names {
            let name = CaptureTagParser.normalizedDisplayName(proposedName)
            let normalized = CaptureTagParser.normalize(name)
            guard !normalized.isEmpty else { continue }
            if let existing = tags.first(where: { $0.normalizedName == normalized }) {
                resolved.append(existing)
            } else {
                let tag = CaptureTag(
                    name: name,
                    normalizedName: normalized,
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(tag)
                tags.append(tag)
                resolved.append(tag)
            }
        }
        return resolved
    }

    private static func record(from item: CaptureItem, previous: CaptureRecord?) -> CaptureRecord {
        let tagNames = item.tags.map(\.name).sorted()
        var record = CaptureRecord(
            id: item.id,
            text: item.text,
            kind: item.kind == .task ? .task : .note,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            dueDate: item.dueDate,
            isPinned: item.isPinned,
            archivedAt: item.archivedAt,
            trashedAt: item.trashedAt,
            folderID: item.list?.id,
            folderName: item.list?.name,
            tags: tagNames,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            fieldVersions: previous?.fieldVersions
        )
        guard let previous else { return record }

        var changed: Set<CaptureField> = []
        if previous.text != record.text { changed.insert(.text) }
        if previous.kind != record.kind
            || previous.isCompleted != record.isCompleted
            || previous.completedAt != record.completedAt
            || previous.dueDate != record.dueDate {
            changed.insert(.task)
        }
        if previous.isPinned != record.isPinned { changed.insert(.pin) }
        if previous.archivedAt != record.archivedAt || previous.trashedAt != record.trashedAt {
            changed.insert(.lifecycle)
        }
        if previous.folderID != record.folderID || previous.folderName != record.folderName {
            changed.insert(.folder)
        }
        if previous.tags != tagNames { changed.insert(.tags) }
        record.markChanged(changed, at: item.updatedAt)
        return record
    }

    private static func hasSameValues(_ record: CaptureRecord, as item: CaptureItem) -> Bool {
        record.text == item.text
            && localKind(record.kind) == item.kind
            && (record.kind == .task && record.isCompleted) == item.isCompleted
            && (record.kind == .task && record.isCompleted ? record.completedAt : nil) == item.completedAt
            && record.dueDate == item.dueDate
            && record.isPinned == item.isPinned
            && record.archivedAt == item.archivedAt
            && record.trashedAt == item.trashedAt
            && record.folderID == item.list?.id
            && record.folderName == item.list?.name
            && record.tags.sorted() == item.tags.map(\.name).sorted()
    }

    private static func localKind(_ kind: NotchCaptureSync.CaptureKind) -> CaptureItemKind {
        kind == .task ? .task : .note
    }
}
