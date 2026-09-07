import Foundation
import NotchCaptureSync
import Observation

@MainActor
@Observable
final class WatchCaptureModel {
    private let store = CaptureSyncStore(containerIdentifier: "iCloud.com.lipe.notchcapture")
    private var hasStarted = false

    var records: [CaptureRecord] = []
    var isSyncing = false
    var message: String?

    var recent: [CaptureRecord] {
        records
            .filter { $0.archivedAt == nil && $0.trashedAt == nil && !$0.isCompleted }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { $0 }
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
            message = nil
        } catch {
            records = await store.records()
            message = "Offline"
        }
    }

    func capture(_ text: String, kind: CaptureKind) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let now = Date()
        let record = CaptureRecord(
            id: UUID(), text: trimmed, kind: kind,
            isCompleted: false, completedAt: nil, dueDate: nil, isPinned: false,
            archivedAt: nil, trashedAt: nil, folderID: nil, folderName: nil,
            tags: Self.tags(in: trimmed), createdAt: now, updatedAt: now
        )
        do {
            try await store.upsert(record)
            records = await store.records()
            message = "Captured"
            Task { await synchronize() }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func toggleCompletion(_ record: CaptureRecord) async {
        var updated = records.first(where: { $0.id == record.id }) ?? record
        guard updated.kind == .task else { return }
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? .now : nil
        updated.markChanged([.task], at: .now)
        do {
            try await store.upsert(updated)
            records = await store.records()
            Task { await synchronize() }
        } catch {
            message = error.localizedDescription
        }
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
