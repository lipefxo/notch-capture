@preconcurrency import CloudKit
import Foundation

public actor CloudKitPrivateDatabaseClient {
    public static let defaultRecordType = "CaptureRecord"

    private enum Field {
        static let text = "text"
        static let kind = "kind"
        static let isCompleted = "isCompleted"
        static let completedAt = "completedAt"
        static let dueDate = "dueDate"
        static let isPinned = "isPinned"
        static let archivedAt = "archivedAt"
        static let trashedAt = "trashedAt"
        static let folderID = "folderID"
        static let folderName = "folderName"
        static let tags = "tags"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
        static let fieldVersions = "fieldVersions"
    }

    private let database: CKDatabase
    private let recordType: String

    public init(containerIdentifier: String, recordType: String = defaultRecordType) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        self.recordType = recordType
    }

    public func fetchAll() async throws -> [CaptureRecord] {
        var fetched: [CaptureRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let results: [(CKRecord.ID, Result<CKRecord, any Error>)]
            if let currentCursor = cursor {
                let response = try await database.records(continuingMatchFrom: currentCursor)
                results = response.matchResults
                cursor = response.queryCursor
            } else {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let response = try await database.records(matching: query)
                results = response.matchResults
                cursor = response.queryCursor
            }

            for (_, result) in results {
                if let record = try? result.get(), let capture = decode(record) {
                    fetched.append(capture)
                }
            }
        } while cursor != nil

        return fetched.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Applies last-write-wins before saving, so an offline device cannot
    /// overwrite a newer value already present in CloudKit.
    @discardableResult
    public func save(_ capture: CaptureRecord) async throws -> CaptureRecord {
        let recordID = CKRecord.ID(recordName: capture.id.uuidString)
        let record: CKRecord
        var valueToSave = capture
        do {
            record = try await database.record(for: recordID)
            if let remote = decode(record) {
                valueToSave = CaptureRecordMerger.winner(capture, remote)
                if valueToSave == remote { return remote }
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        encode(valueToSave, into: record)
        _ = try await database.save(record)
        return valueToSave
    }

    public func delete(id: UUID) async throws {
        try await delete(id: id, unlessUpdatedAfter: .distantFuture)
    }

    /// Deletes unless CloudKit contains a record newer than the local deletion.
    /// Returns that newer record when deletion loses the LWW comparison.
    @discardableResult
    public func delete(
        id: UUID,
        unlessUpdatedAfter deletedAt: Date
    ) async throws -> CaptureRecord? {
        do {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            let remoteRecord = try await database.record(for: recordID)
            if let remote = decode(remoteRecord), remote.updatedAt > deletedAt {
                return remote
            }
            _ = try await database.deleteRecord(withID: recordID)
            return nil
        } catch let error as CKError where error.code == .unknownItem {
            // Deleting an already-absent record is idempotent.
            return nil
        }
    }

    private func encode(_ capture: CaptureRecord, into record: CKRecord) {
        record[Field.text] = capture.text as CKRecordValue
        record[Field.kind] = capture.kind.rawValue as CKRecordValue
        record[Field.isCompleted] = capture.isCompleted as CKRecordValue
        record[Field.completedAt] = capture.completedAt as CKRecordValue?
        record[Field.dueDate] = capture.dueDate as CKRecordValue?
        record[Field.isPinned] = capture.isPinned as CKRecordValue
        record[Field.archivedAt] = capture.archivedAt as CKRecordValue?
        record[Field.trashedAt] = capture.trashedAt as CKRecordValue?
        record[Field.folderID] = capture.folderID?.uuidString as CKRecordValue?
        record[Field.folderName] = capture.folderName as CKRecordValue?
        record[Field.tags] = capture.tags as CKRecordValue
        record[Field.createdAt] = capture.createdAt as CKRecordValue
        record[Field.updatedAt] = capture.updatedAt as CKRecordValue
        record[Field.deletedAt] = capture.deletedAt as CKRecordValue?
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let data = try? encoder.encode(capture.fieldVersions) {
            record[Field.fieldVersions] = data as CKRecordValue
        }
    }

    private func decode(_ record: CKRecord) -> CaptureRecord? {
        guard
            let id = UUID(uuidString: record.recordID.recordName),
            let text = record[Field.text] as? String,
            let kindValue = record[Field.kind] as? String,
            let kind = CaptureKind(rawValue: kindValue),
            let createdAt = record[Field.createdAt] as? Date,
            let updatedAt = record[Field.updatedAt] as? Date
        else { return nil }

        let folderID = (record[Field.folderID] as? String).flatMap(UUID.init(uuidString:))
        let fieldVersions: [CaptureField: Date]?
        if let data = record[Field.fieldVersions] as? Data {
            fieldVersions = CaptureRecord.decodeFieldVersions(from: data, fallback: updatedAt)
        } else {
            fieldVersions = nil
        }
        return CaptureRecord(
            id: id,
            text: text,
            kind: kind,
            isCompleted: record[Field.isCompleted] as? Bool ?? false,
            completedAt: record[Field.completedAt] as? Date,
            dueDate: record[Field.dueDate] as? Date,
            isPinned: record[Field.isPinned] as? Bool ?? false,
            archivedAt: record[Field.archivedAt] as? Date,
            trashedAt: record[Field.trashedAt] as? Date,
            folderID: folderID,
            folderName: record[Field.folderName] as? String,
            tags: record[Field.tags] as? [String] ?? [],
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: record[Field.deletedAt] as? Date,
            fieldVersions: fieldVersions
        )
    }
}
