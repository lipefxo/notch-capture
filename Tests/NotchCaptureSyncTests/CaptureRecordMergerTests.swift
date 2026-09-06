import Foundation
import Testing
@testable import NotchCaptureSync

private enum LegacyField: String, Codable, Hashable {
    case text, kind, completion, dueDate, pin, lifecycle, folder, tags
}

struct CaptureRecordMergerTests {
    @Test func laterUpdateWinsAndOutputOrderIsStable() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let old = CaptureRecord(id: secondID, text: "old", updatedAt: early)
        let new = CaptureRecord(id: secondID, text: "new", updatedAt: late)
        let other = CaptureRecord(id: firstID, text: "first", updatedAt: early)

        let merged = CaptureRecordMerger.merge(local: [old], remote: [new, other])

        #expect(merged.map(\.id) == [firstID, secondID])
        #expect(merged.last?.text == "new")
    }

    @Test func equalTimestampConflictConvergesRegardlessOfInputOrder() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let timestamp = Date(timeIntervalSince1970: 500)
        let alpha = CaptureRecord(id: id, text: "alpha", updatedAt: timestamp)
        let omega = CaptureRecord(id: id, text: "omega", updatedAt: timestamp)

        let forward = CaptureRecordMerger.merge(local: [alpha], remote: [omega])
        let reverse = CaptureRecordMerger.merge(local: [omega], remote: [alpha])

        #expect(forward == reverse)
    }

    @Test func statusAndFolderAreDerivedFromPortableFields() {
        let folderID = UUID()
        let record = CaptureRecord(
            text: "Ship companion",
            kind: .task,
            isCompleted: true,
            folderID: folderID,
            folderName: "Roadmap",
            tags: ["ios", "watch"]
        )

        #expect(record.status == .completed)
        #expect(record.folder == CaptureFolder(id: folderID, name: "Roadmap"))
    }

    @Test func unrelatedConcurrentEditsMergeAtFieldLevel() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let base = CaptureRecord(text: "Original", createdAt: baseDate, updatedAt: baseDate)

        var macTextEdit = base
        macTextEdit.text = "Edited on Mac"
        macTextEdit.markChanged([.text], at: Date(timeIntervalSince1970: 200))

        var watchCompletion = base
        watchCompletion.kind = .task
        watchCompletion.isCompleted = true
        watchCompletion.completedAt = Date(timeIntervalSince1970: 300)
        watchCompletion.markChanged([.task], at: Date(timeIntervalSince1970: 300))

        let merged = CaptureRecordMerger.winner(macTextEdit, watchCompletion)

        #expect(merged.text == "Edited on Mac")
        #expect(merged.kind == .task)
        #expect(merged.isCompleted)
        #expect(merged.completedAt == Date(timeIntervalSince1970: 300))
    }

    @Test func fieldMergeIsAssociativeAcrossThreeDevices() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let base = CaptureRecord(text: "Base", createdAt: timestamp, updatedAt: timestamp)
        var phone = base
        phone.text = "Phone"
        phone.markChanged([.text], at: Date(timeIntervalSince1970: 200))
        var watch = base
        watch.isPinned = true
        watch.markChanged([.pin], at: Date(timeIntervalSince1970: 300))
        var mac = base
        mac.text = "Mac"
        mac.kind = .task
        mac.dueDate = Date(timeIntervalSince1970: 400)
        mac.markChanged([.text], at: Date(timeIntervalSince1970: 200))
        mac.markChanged([.task], at: Date(timeIntervalSince1970: 400))

        let leftGrouped = CaptureRecordMerger.winner(
            CaptureRecordMerger.winner(phone, watch),
            mac
        )
        let rightGrouped = CaptureRecordMerger.winner(
            phone,
            CaptureRecordMerger.winner(watch, mac)
        )

        #expect(leftGrouped == rightGrouped)
        #expect(leftGrouped.isPinned)
        #expect(leftGrouped.dueDate == Date(timeIntervalSince1970: 400))
    }

    @Test func tombstoneSurvivesAConcurrentUnrelatedEdit() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let base = CaptureRecord(text: "Delete me", createdAt: baseDate, updatedAt: baseDate)

        var deleted = base
        deleted.deletedAt = Date(timeIntervalSince1970: 300)
        deleted.markChanged([.existence], at: Date(timeIntervalSince1970: 300))

        var offlineEdit = base
        offlineEdit.text = "Edited while offline"
        offlineEdit.markChanged([.text], at: Date(timeIntervalSince1970: 400))

        let merged = CaptureRecordMerger.winner(deleted, offlineEdit)

        #expect(merged.deletedAt == Date(timeIntervalSince1970: 300))
        #expect(merged.text == "Edited while offline")
    }

    @Test func equalVersionLiveCopyCannotClearATombstone() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let base = CaptureRecord(text: "Delete me", createdAt: baseDate, updatedAt: baseDate)
        var tombstone = base
        tombstone.deletedAt = Date(timeIntervalSince1970: 300)
        tombstone.markChanged([.existence], at: Date(timeIntervalSince1970: 300))

        var crashWindowCopy = tombstone
        crashWindowCopy.deletedAt = nil

        let forward = CaptureRecordMerger.winner(tombstone, crashWindowCopy)
        let reverse = CaptureRecordMerger.winner(crashWindowCopy, tombstone)

        #expect(forward.deletedAt == tombstone.deletedAt)
        #expect(reverse.deletedAt == tombstone.deletedAt)
        #expect(forward == reverse)
    }

    @Test func noteTaskStateMergesAsOneValidUnit() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let base = CaptureRecord(text: "Draft", createdAt: baseDate, updatedAt: baseDate)

        var completedTask = base
        completedTask.kind = .task
        completedTask.isCompleted = true
        completedTask.completedAt = Date(timeIntervalSince1970: 200)
        completedTask.dueDate = Date(timeIntervalSince1970: 500)
        completedTask.markChanged([.task], at: Date(timeIntervalSince1970: 200))

        var convertedNote = base
        convertedNote.kind = .note
        convertedNote.isCompleted = false
        convertedNote.completedAt = nil
        convertedNote.dueDate = nil
        convertedNote.markChanged([.task], at: Date(timeIntervalSince1970: 300))

        let merged = CaptureRecordMerger.winner(completedTask, convertedNote)

        #expect(merged.kind == .note)
        #expect(!merged.isCompleted)
        #expect(merged.completedAt == nil)
        #expect(merged.dueDate == nil)
    }

    @Test func legacyFieldVersionsMigrateWithoutInventingAnUndelete() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode([
            LegacyField.text: Date(timeIntervalSince1970: 200),
            LegacyField.kind: Date(timeIntervalSince1970: 250),
            LegacyField.completion: Date(timeIntervalSince1970: 300),
            LegacyField.dueDate: Date(timeIntervalSince1970: 275),
        ])

        let versions = CaptureRecord.decodeFieldVersions(
            from: data,
            fallback: Date(timeIntervalSince1970: 100)
        )

        #expect(versions[.text] == Date(timeIntervalSince1970: 200))
        #expect(versions[.task] == Date(timeIntervalSince1970: 300))
        #expect(versions[.existence] == .distantPast)
    }
}
