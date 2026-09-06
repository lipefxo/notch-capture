import Foundation
import NotchCaptureSync
import Observation

@MainActor
@Observable
final class MobileCaptureModel {
    enum Filter: String, CaseIterable, Identifiable {
        case inbox = "Inbox"
        case tasks = "Tasks"
        case due = "Due"
        case completed = "Completed"
        case archive = "Archive"
        case trash = "Trash"

        var id: Self { self }
    }

    private let store = CaptureSyncStore(containerIdentifier: "iCloud.com.lipe.notchcapture")
    private var hasStarted = false

    var records: [CaptureRecord] = []
    var filter: Filter = .inbox
    var searchText = ""
    var isSyncing = false
    var lastSyncedAt: Date?
    var syncIssue: String?
    var errorMessage: String?

    var visibleRecords: [CaptureRecord] {
        records
            .filter(matchesFilter)
            .filter { record in
                guard !searchText.isEmpty else { return true }
                return record.text.localizedCaseInsensitiveContains(searchText)
                    || record.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
                    || (record.folderName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .sorted(by: comesBefore)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        records = await store.records()
        await synchronize()
    }

    func synchronize() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            records = try await store.synchronize()
            lastSyncedAt = .now
            syncIssue = nil
            errorMessage = nil
        } catch {
            records = await store.records()
            syncIssue = "Saved offline"
        }
    }

    func capture(_ text: String, as kind: CaptureKind) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let now = Date()
        let record = CaptureRecord(
            id: UUID(),
            text: trimmed,
            kind: kind,
            isCompleted: false,
            completedAt: nil,
            dueDate: nil,
            isPinned: false,
            archivedAt: nil,
            trashedAt: nil,
            folderID: nil,
            folderName: nil,
            tags: Self.tags(in: trimmed),
            createdAt: now,
            updatedAt: now
        )
        return await save(record)
    }

    func update(
        _ record: CaptureRecord,
        text: String,
        kind: CaptureKind,
        dueDate: Date?
    ) async {
        var updated = current(record)
        var changedFields: Set<CaptureField> = []
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        if trimmedText != record.text {
            updated.text = trimmedText
            updated.tags = Self.tags(in: trimmedText)
            changedFields.formUnion([.text, .tags])
        }
        if kind != record.kind {
            updated.kind = kind
            changedFields.insert(.task)
            if kind == .note {
                updated.isCompleted = false
                updated.completedAt = nil
                updated.dueDate = nil
            }
        }
        if kind == .task {
            let normalizedDueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
            if normalizedDueDate != record.dueDate {
                updated.dueDate = normalizedDueDate
                changedFields.insert(.task)
            }
        }
        guard !changedFields.isEmpty else { return }
        updated.markChanged(changedFields, at: .now)
        await save(updated)
    }

    func toggleCompletion(_ record: CaptureRecord) async {
        var updated = current(record)
        let fields: Set<CaptureField> = [.task]
        if updated.kind == .note {
            updated.kind = .task
        }
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? .now : nil
        updated.markChanged(fields, at: .now)
        await save(updated)
    }

    func togglePinned(_ record: CaptureRecord) async {
        var updated = current(record)
        updated.isPinned.toggle()
        updated.markChanged([.pin], at: .now)
        await save(updated)
    }

    func archive(_ record: CaptureRecord) async {
        var updated = current(record)
        updated.archivedAt = .now
        updated.trashedAt = nil
        updated.markChanged([.lifecycle], at: .now)
        await save(updated)
    }

    func trash(_ record: CaptureRecord) async {
        var updated = current(record)
        updated.trashedAt = .now
        updated.markChanged([.lifecycle], at: .now)
        await save(updated)
    }

    func restore(_ record: CaptureRecord) async {
        var updated = current(record)
        updated.archivedAt = nil
        updated.trashedAt = nil
        updated.markChanged([.lifecycle], at: .now)
        await save(updated)
    }

    @discardableResult
    private func save(_ record: CaptureRecord) async -> Bool {
        do {
            try await store.upsert(record)
            records = await store.records()
            errorMessage = nil
            Task { await synchronize() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func current(_ record: CaptureRecord) -> CaptureRecord {
        records.first(where: { $0.id == record.id }) ?? record
    }

    private func matchesFilter(_ record: CaptureRecord) -> Bool {
        switch filter {
        case .inbox:
            record.archivedAt == nil && record.trashedAt == nil && (
                !record.isCompleted
                    || (record.completedAt?.addingTimeInterval(24 * 60 * 60) ?? .distantPast) > .now
            )
        case .tasks:
            record.archivedAt == nil && record.trashedAt == nil && record.kind == .task && !record.isCompleted
        case .due:
            record.archivedAt == nil && record.trashedAt == nil && record.dueDate != nil && !record.isCompleted
        case .completed:
            record.trashedAt == nil && record.isCompleted
        case .archive:
            record.archivedAt != nil && record.trashedAt == nil
        case .trash:
            record.trashedAt != nil
        }
    }

    private func comesBefore(_ lhs: CaptureRecord, _ rhs: CaptureRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func tags(in text: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: #"(?:^|\s)@([\p{L}\p{N}_-]+)"#)
        let range = NSRange(text.startIndex..., in: text)
        var seen: Set<String> = []
        return expression?.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[range])
            return seen.insert(name.lowercased()).inserted ? name : nil
        } ?? []
    }
}
