import Foundation

public enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case note
    case task
}

public enum CaptureStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case archived
    case trashed
}

/// Independently versioned groups prevent a small action on one device from
/// replacing unrelated newer data from another device.
public enum CaptureField: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case task
    case pin
    case lifecycle
    case folder
    case tags
    case existence
}

private enum LegacyCaptureField: String, Codable, Hashable {
    case text, kind, completion, dueDate, pin, lifecycle, folder, tags
}

public struct CaptureFolder: Codable, Equatable, Sendable {
    public var id: UUID?
    public var name: String

    public init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

/// A platform-neutral representation of a capture that can be shared by the
/// macOS, iOS, and watchOS apps without importing SwiftData.
public struct CaptureRecord: Codable, Identifiable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id, text, kind, isCompleted, completedAt, dueDate, isPinned
        case archivedAt, trashedAt, folderID, folderName, tags, createdAt, updatedAt
        case deletedAt
        case fieldVersions
    }

    public var id: UUID
    public var text: String
    public var kind: CaptureKind
    public var isCompleted: Bool
    public var completedAt: Date?
    public var dueDate: Date?
    public var isPinned: Bool
    public var archivedAt: Date?
    public var trashedAt: Date?
    public var folderID: UUID?
    public var folderName: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var fieldVersions: [CaptureField: Date]

    public init(
        id: UUID = UUID(),
        text: String,
        kind: CaptureKind = .note,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        isPinned: Bool = false,
        archivedAt: Date? = nil,
        trashedAt: Date? = nil,
        folderID: UUID? = nil,
        folderName: String? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        fieldVersions: [CaptureField: Date]? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.isPinned = isPinned
        self.archivedAt = archivedAt
        self.trashedAt = trashedAt
        self.folderID = folderID
        self.folderName = folderName
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.fieldVersions = fieldVersions
            ?? Dictionary(uniqueKeysWithValues: CaptureField.allCases.map { ($0, updatedAt) })
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        kind = try values.decode(CaptureKind.self, forKey: .kind)
        isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        trashedAt = try values.decodeIfPresent(Date.self, forKey: .trashedAt)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        folderName = try values.decodeIfPresent(String.self, forKey: .folderName)
        tags = try values.decode([String].self, forKey: .tags)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        let decodedUpdatedAt = try values.decode(Date.self, forKey: .updatedAt)
        updatedAt = decodedUpdatedAt
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        if let current = try? values.decode([CaptureField: Date].self, forKey: .fieldVersions) {
            fieldVersions = Self.complete(current, fallback: decodedUpdatedAt)
        } else if let legacy = try? values.decode(
            [LegacyCaptureField: Date].self,
            forKey: .fieldVersions
        ) {
            fieldVersions = Self.migrate(legacy, fallback: decodedUpdatedAt)
        } else {
            fieldVersions = Self.defaultFieldVersions(at: decodedUpdatedAt)
        }
    }

    public var status: CaptureStatus {
        if trashedAt != nil { return .trashed }
        if archivedAt != nil { return .archived }
        if isCompleted { return .completed }
        return .active
    }

    public var folder: CaptureFolder? {
        guard let folderName else { return nil }
        return CaptureFolder(id: folderID, name: folderName)
    }

    public mutating func markChanged(_ fields: Set<CaptureField>, at date: Date = .now) {
        for field in fields { fieldVersions[field] = date }
        updatedAt = max(updatedAt, date)
    }

    public func version(for field: CaptureField) -> Date {
        fieldVersions[field] ?? updatedAt
    }

    static func decodeFieldVersions(from data: Data, fallback: Date) -> [CaptureField: Date] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let current = try? decoder.decode([CaptureField: Date].self, from: data) {
            return complete(current, fallback: fallback)
        }
        if let legacy = try? decoder.decode([LegacyCaptureField: Date].self, from: data) {
            return migrate(legacy, fallback: fallback)
        }
        return defaultFieldVersions(at: fallback)
    }

    private static func defaultFieldVersions(at date: Date) -> [CaptureField: Date] {
        var versions = Dictionary(uniqueKeysWithValues: CaptureField.allCases.map { ($0, date) })
        versions[.existence] = .distantPast
        return versions
    }

    private static func complete(
        _ versions: [CaptureField: Date],
        fallback: Date
    ) -> [CaptureField: Date] {
        var result = versions
        for field in CaptureField.allCases where result[field] == nil {
            result[field] = field == .existence ? .distantPast : fallback
        }
        return result
    }

    private static func migrate(
        _ versions: [LegacyCaptureField: Date],
        fallback: Date
    ) -> [CaptureField: Date] {
        let taskVersions = [versions[.kind], versions[.completion], versions[.dueDate]].compactMap { $0 }
        return [
            .text: versions[.text] ?? fallback,
            .task: taskVersions.max() ?? fallback,
            .pin: versions[.pin] ?? fallback,
            .lifecycle: versions[.lifecycle] ?? fallback,
            .folder: versions[.folder] ?? fallback,
            .tags: versions[.tags] ?? fallback,
            .existence: .distantPast,
        ]
    }
}

/// Deterministic last-write-wins merging for locally cached and remote records.
public enum CaptureRecordMerger {
    public static func merge(
        local: [CaptureRecord],
        remote: [CaptureRecord]
    ) -> [CaptureRecord] {
        var recordsByID: [UUID: CaptureRecord] = [:]

        for record in local + remote {
            guard let current = recordsByID[record.id] else {
                recordsByID[record.id] = record
                continue
            }
            recordsByID[record.id] = winner(current, record)
        }

        return recordsByID.values.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Merges independently versioned field groups. Equal timestamps use a
    /// canonical record tie-break so every device reaches the same result.
    public static func winner(_ lhs: CaptureRecord, _ rhs: CaptureRecord) -> CaptureRecord {
        guard lhs.id == rhs.id else {
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt ? lhs : rhs }
            return lhs.id.uuidString > rhs.id.uuidString ? lhs : rhs
        }

        var merged = lhs
        merged.createdAt = min(lhs.createdAt, rhs.createdAt)
        merged.updatedAt = max(lhs.updatedAt, rhs.updatedAt)

        for field in CaptureField.allCases {
            let lhsVersion = lhs.version(for: field)
            let rhsVersion = rhs.version(for: field)
            let source: CaptureRecord
            if lhsVersion == rhsVersion {
                if field == .existence, lhs.deletedAt != nil, rhs.deletedAt == nil {
                    // Deletion is permanent. If a crash leaves an old live copy
                    // carrying the tombstone's version, it must not resurrect it.
                    source = lhs
                } else if field == .existence, lhs.deletedAt == nil, rhs.deletedAt != nil {
                    source = rhs
                } else {
                    source = canonicalBytes(lhs, for: field).lexicographicallyPrecedes(
                        canonicalBytes(rhs, for: field)
                    ) ? rhs : lhs
                }
            } else {
                source = lhsVersion > rhsVersion ? lhs : rhs
            }
            merged.copy(field, from: source)
            merged.fieldVersions[field] = max(lhsVersion, rhsVersion)
        }
        return merged
    }

    private static func canonicalBytes(_ record: CaptureRecord, for field: CaptureField) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return (try? encoder.encode(ComparableFieldValue(record: record, field: field))) ?? Data()
    }
}

private enum ComparableFieldValue: Encodable {
    case text(String)
    case task(kind: CaptureKind, isCompleted: Bool, completedAt: Date?, dueDate: Date?)
    case pin(Bool)
    case lifecycle(archivedAt: Date?, trashedAt: Date?)
    case folder(id: UUID?, name: String?)
    case tags([String])
    case existence(Date?)

    init(record: CaptureRecord, field: CaptureField) {
        switch field {
        case .text: self = .text(record.text)
        case .task: self = .task(
            kind: record.kind,
            isCompleted: record.isCompleted,
            completedAt: record.completedAt,
            dueDate: record.dueDate
        )
        case .pin: self = .pin(record.isPinned)
        case .lifecycle: self = .lifecycle(
            archivedAt: record.archivedAt,
            trashedAt: record.trashedAt
        )
        case .folder: self = .folder(id: record.folderID, name: record.folderName)
        case .tags: self = .tags(record.tags)
        case .existence: self = .existence(record.deletedAt)
        }
    }
}

private extension CaptureRecord {
    mutating func copy(_ field: CaptureField, from source: CaptureRecord) {
        switch field {
        case .text:
            text = source.text
        case .task:
            kind = source.kind
            isCompleted = source.isCompleted
            completedAt = source.completedAt
            dueDate = source.dueDate
            if kind == .note {
                isCompleted = false
                completedAt = nil
                dueDate = nil
            }
        case .pin:
            isPinned = source.isPinned
        case .lifecycle:
            archivedAt = source.archivedAt
            trashedAt = source.trashedAt
        case .folder:
            folderID = source.folderID
            folderName = source.folderName
        case .tags:
            tags = source.tags
        case .existence:
            deletedAt = source.deletedAt
        }
    }
}
