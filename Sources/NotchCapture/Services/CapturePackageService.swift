import Foundation
import SwiftData
import UniformTypeIdentifiers

struct CapturePackageManifest: Codable, Sendable {
    static let currentVersion = 6

    let schemaVersion: Int
    let exportedAt: Date
    let lists: [ListRecord]
    let tags: [TagRecord]?
    let items: [ItemRecord]

    struct ListRecord: Codable, Sendable {
        let id: UUID
        let name: String
        let sortOrder: Int
        let createdAt: Date
        let updatedAt: Date
    }

    struct TagRecord: Codable, Sendable {
        let id: UUID
        let name: String
        let colorSeed: Double?
        let createdAt: Date
        let updatedAt: Date
    }

    struct ItemRecord: Codable, Sendable {
        let id: UUID
        let text: String
        let kind: CaptureItemKind
        let isCompleted: Bool
        let completedAt: Date?
        let dueDate: Date?
        let isPinned: Bool
        let archivedAt: Date?
        let trashedAt: Date?
        let sortOrder: Int?
        let createdAt: Date
        let updatedAt: Date
        let origin: CaptureOrigin
        let source: CaptureSource
        let listID: UUID?
        let tagIDs: [UUID]?
        let attachments: [AttachmentRecord]
        /// Decode-only compatibility marker for package schemas 1...5.
        /// It is never emitted in v6 exports.
        let legacyReusableAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, text, kind, isCompleted, completedAt, dueDate, isPinned
            case archivedAt, trashedAt, sortOrder, createdAt, updatedAt, origin
            case source, listID, tagIDs, attachments, reusableAt
        }

        init(
            id: UUID,
            text: String,
            kind: CaptureItemKind,
            isCompleted: Bool,
            completedAt: Date?,
            dueDate: Date?,
            isPinned: Bool,
            archivedAt: Date?,
            trashedAt: Date?,
            sortOrder: Int?,
            createdAt: Date,
            updatedAt: Date,
            origin: CaptureOrigin,
            source: CaptureSource,
            listID: UUID?,
            tagIDs: [UUID]?,
            attachments: [AttachmentRecord]
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
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.origin = origin
            self.source = source
            self.listID = listID
            self.tagIDs = tagIDs
            self.attachments = attachments
            self.legacyReusableAt = nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            text = try container.decode(String.self, forKey: .text)
            kind = try container.decode(CaptureItemKind.self, forKey: .kind)
            isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
            completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
            dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
            isPinned = try container.decode(Bool.self, forKey: .isPinned)
            archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
            trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
            sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            origin = try container.decode(CaptureOrigin.self, forKey: .origin)
            source = try container.decode(CaptureSource.self, forKey: .source)
            listID = try container.decodeIfPresent(UUID.self, forKey: .listID)
            tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs)
            attachments = try container.decode([AttachmentRecord].self, forKey: .attachments)
            legacyReusableAt = try container.decodeIfPresent(Date.self, forKey: .reusableAt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encode(kind, forKey: .kind)
            try container.encode(isCompleted, forKey: .isCompleted)
            try container.encodeIfPresent(completedAt, forKey: .completedAt)
            try container.encodeIfPresent(dueDate, forKey: .dueDate)
            try container.encode(isPinned, forKey: .isPinned)
            try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
            try container.encodeIfPresent(trashedAt, forKey: .trashedAt)
            try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(origin, forKey: .origin)
            try container.encode(source, forKey: .source)
            try container.encodeIfPresent(listID, forKey: .listID)
            try container.encodeIfPresent(tagIDs, forKey: .tagIDs)
            try container.encode(attachments, forKey: .attachments)
        }
    }

    struct AttachmentRecord: Codable, Sendable {
        let id: UUID
        let kind: AttachmentKind
        let typeIdentifier: String
        let originalFilename: String
        let packagePath: String?
        let url: URL?
        let pageTitle: String?
        let faviconPackagePath: String?
        let faviconTypeIdentifier: String?
        let order: Int
        let createdAt: Date
    }
}

struct CapturePackageImportResult: Equatable, Sendable {
    let importedItemCount: Int
    let skippedDuplicateCount: Int
    let reassignedIdentifierCount: Int
}

@MainActor
final class CapturePackageService {
    private let modelContext: ModelContext
    private let attachmentStore: AttachmentStore
    private let fileManager: FileManager

    init(
        modelContext: ModelContext,
        attachmentStore: AttachmentStore,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.attachmentStore = attachmentStore
        self.fileManager = fileManager
    }

    @discardableResult
    func export(to destination: URL) throws -> URL {
        guard destination.pathExtension.lowercased() == "notchcapture" else {
            throw CapturePackageError.invalidExtension
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CapturePackageError.destinationExists
        }

        let items = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        let lists = try modelContext.fetch(FetchDescriptor<ItemList>())
        let tags = try modelContext.fetch(FetchDescriptor<CaptureTag>())
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).notchcapture", isDirectory: true)
        let attachmentsDirectory = temporary.appendingPathComponent("attachments", isDirectory: true)
        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        var didFinish = false
        defer { if !didFinish { try? fileManager.removeItem(at: temporary) } }

        let listRecords = lists.map {
            CapturePackageManifest.ListRecord(
                id: $0.id,
                name: $0.name,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let tagRecords = tags.map {
            CapturePackageManifest.TagRecord(
                id: $0.id,
                name: $0.name,
                colorSeed: $0.colorSeed,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let itemRecords = try items.map { item in
            let attachmentRecords = try item.attachments.sorted(by: { $0.order < $1.order }).map { attachment in
                var packagePath: String?
                if let relativePath = attachment.relativePath {
                    let source = try attachmentStore.resolve(relativePath: relativePath)
                    guard fileManager.fileExists(atPath: source.path) else {
                        throw CapturePackageError.missingAttachment(relativePath)
                    }
                    let exportName = "\(attachment.id.uuidString)-\(sanitized(attachment.originalFilename))"
                    let relativeExportPath = "attachments/\(exportName)"
                    try fileManager.copyItem(at: source, to: temporary.appendingPathComponent(relativeExportPath))
                    packagePath = relativeExportPath
                }
                var faviconPackagePath: String?
                if let relativePath = attachment.faviconRelativePath {
                    let source = try attachmentStore.resolve(relativePath: relativePath)
                    guard fileManager.fileExists(atPath: source.path) else {
                        throw CapturePackageError.missingAttachment(relativePath)
                    }
                    let extensionFromType = attachment.faviconTypeIdentifier
                        .flatMap { UTType($0)?.preferredFilenameExtension }
                    let extensionFromPath = source.pathExtension
                    let filenameExtension = extensionFromType
                        ?? (extensionFromPath.isEmpty ? "img" : extensionFromPath)
                    let relativeExportPath = "attachments/\(attachment.id.uuidString)-favicon.\(filenameExtension)"
                    try fileManager.copyItem(at: source, to: temporary.appendingPathComponent(relativeExportPath))
                    faviconPackagePath = relativeExportPath
                }
                return CapturePackageManifest.AttachmentRecord(
                    id: attachment.id,
                    kind: attachment.kind,
                    typeIdentifier: attachment.typeIdentifier,
                    originalFilename: attachment.originalFilename,
                    packagePath: packagePath,
                    url: attachment.url,
                    pageTitle: attachment.pageTitle,
                    faviconPackagePath: faviconPackagePath,
                    faviconTypeIdentifier: attachment.faviconTypeIdentifier,
                    order: attachment.order,
                    createdAt: attachment.createdAt
                )
            }
            return CapturePackageManifest.ItemRecord(
                id: item.id,
                text: item.text,
                kind: item.kind,
                isCompleted: item.isCompleted,
                completedAt: item.completedAt,
                dueDate: item.dueDate,
                isPinned: item.isPinned,
                archivedAt: item.archivedAt,
                trashedAt: item.trashedAt,
                sortOrder: item.sortOrder,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                origin: item.origin,
                source: item.source,
                listID: item.list?.id,
                tagIDs: item.tags.map(\.id).sorted { $0.uuidString < $1.uuidString },
                attachments: attachmentRecords
            )
        }

        let manifest = CapturePackageManifest(
            schemaVersion: CapturePackageManifest.currentVersion,
            exportedAt: .now,
            lists: listRecords,
            tags: tagRecords,
            items: itemRecords
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: temporary.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try fileManager.moveItem(at: temporary, to: destination)
        didFinish = true
        return destination
    }

    func importPackage(at packageURL: URL) throws -> CapturePackageImportResult {
        guard packageURL.pathExtension.lowercased() == "notchcapture" else {
            throw CapturePackageError.invalidExtension
        }
        let manifestURL = try validatedChild(path: "manifest.json", of: packageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: CapturePackageManifest
        do {
            manifest = try decoder.decode(CapturePackageManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw CapturePackageError.invalidManifest(error)
        }
        guard (1...CapturePackageManifest.currentVersion).contains(manifest.schemaVersion) else {
            throw CapturePackageError.unsupportedSchema(manifest.schemaVersion)
        }

        let existingItems = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        let existingLists = try modelContext.fetch(FetchDescriptor<ItemList>())
        let existingTags = try modelContext.fetch(FetchDescriptor<CaptureTag>())
        let existingAttachments = try modelContext.fetch(FetchDescriptor<Attachment>())
        var itemsByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var listsByID = Dictionary(uniqueKeysWithValues: existingLists.map { ($0.id, $0) })
        var tagsByID = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.id, $0) })
        var tagsByName = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.normalizedName, $0) })
        var attachmentIDs = Set(existingAttachments.map(\.id))
        var listMapping: [UUID: ItemList] = [:]
        var tagMapping: [UUID: CaptureTag] = [:]
        var storedRelativePaths: [String] = []
        var importedCount = 0
        var duplicateCount = 0
        var reassignedCount = 0

        do {
            for record in manifest.lists {
                if let existing = listsByID[record.id], existing.name == record.name {
                    listMapping[record.id] = existing
                    continue
                }
                let chosenID: UUID
                if listsByID[record.id] == nil {
                    chosenID = record.id
                } else {
                    chosenID = UUID()
                    reassignedCount += 1
                }
                let list = ItemList(
                    id: chosenID,
                    name: record.name,
                    sortOrder: record.sortOrder,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(list)
                listsByID[chosenID] = list
                listMapping[record.id] = list
            }

            for record in manifest.tags ?? [] {
                let displayName = CaptureTagParser.normalizedDisplayName(record.name)
                let normalizedName = CaptureTagParser.normalize(displayName)
                guard !displayName.isEmpty,
                      displayName.allSatisfy(CaptureTagParser.isTagCharacter) else {
                    throw CapturePackageError.invalidTagName(record.name)
                }
                if let existing = tagsByName[normalizedName] {
                    tagMapping[record.id] = existing
                    continue
                }
                let chosenID: UUID
                if tagsByID[record.id] == nil {
                    chosenID = record.id
                } else {
                    chosenID = UUID()
                    reassignedCount += 1
                }
                let tag = CaptureTag(
                    id: chosenID,
                    name: displayName,
                    normalizedName: normalizedName,
                    colorSeed: record.colorSeed ?? TagColorSeed.random(),
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(tag)
                tagsByID[chosenID] = tag
                tagsByName[normalizedName] = tag
                tagMapping[record.id] = tag
            }

            for record in manifest.items {
                // Packages created before v6 may contain retired Quick Snippets.
                // Preserve the user's deletion choice by not importing them.
                guard record.legacyReusableAt == nil else { continue }
                let mappedTags = try (record.tagIDs ?? []).map { tagID in
                    guard let tag = tagMapping[tagID] else { throw CapturePackageError.missingTag(tagID) }
                    return tag
                }
                if let existing = itemsByID[record.id],
                   isExactDuplicate(
                       record,
                       mappedTags: mappedTags,
                       of: existing
                   ) {
                    duplicateCount += 1
                    continue
                }
                let chosenItemID: UUID
                if itemsByID[record.id] == nil {
                    chosenItemID = record.id
                } else {
                    chosenItemID = UUID()
                    reassignedCount += 1
                }

                var attachments: [Attachment] = []
                for attachmentRecord in record.attachments.sorted(by: { $0.order < $1.order }) {
                    let chosenAttachmentID: UUID
                    if attachmentIDs.contains(attachmentRecord.id) {
                        chosenAttachmentID = UUID()
                        reassignedCount += 1
                    } else {
                        chosenAttachmentID = attachmentRecord.id
                    }
                    attachmentIDs.insert(chosenAttachmentID)

                    var storedPath: String?
                    if let packagePath = attachmentRecord.packagePath {
                        let source = try validatedChild(path: packagePath, of: packageURL)
                        guard fileManager.fileExists(atPath: source.path) else {
                            throw CapturePackageError.missingAttachment(packagePath)
                        }
                        let stored = try attachmentStore.storeFile(
                            at: source,
                            id: chosenAttachmentID,
                            kind: attachmentRecord.kind
                        )
                        storedPath = stored.relativePath
                        storedRelativePaths.append(stored.relativePath)
                    }
                    var storedFaviconPath: String?
                    var storedFaviconTypeIdentifier: String?
                    if let faviconPackagePath = attachmentRecord.faviconPackagePath {
                        let source = try validatedChild(path: faviconPackagePath, of: packageURL)
                        guard fileManager.fileExists(atPath: source.path) else {
                            throw CapturePackageError.missingAttachment(faviconPackagePath)
                        }
                        let stored = try attachmentStore.storeFile(
                            at: source,
                            id: UUID(),
                            kind: .image
                        )
                        storedFaviconPath = stored.relativePath
                        storedFaviconTypeIdentifier = stored.typeIdentifier
                        storedRelativePaths.append(stored.relativePath)
                    }
                    attachments.append(
                        Attachment(
                            id: chosenAttachmentID,
                            kind: attachmentRecord.kind,
                            typeIdentifier: attachmentRecord.typeIdentifier,
                            originalFilename: attachmentRecord.originalFilename,
                            relativePath: storedPath,
                            url: attachmentRecord.url,
                            pageTitle: attachmentRecord.pageTitle,
                            faviconRelativePath: storedFaviconPath,
                            faviconTypeIdentifier: attachmentRecord.faviconTypeIdentifier
                                ?? storedFaviconTypeIdentifier,
                            order: attachmentRecord.order,
                            createdAt: attachmentRecord.createdAt
                        )
                    )
                }

                let item = CaptureItem(
                    id: chosenItemID,
                    text: record.text,
                    kind: record.kind,
                    isCompleted: record.isCompleted,
                    completedAt: record.completedAt,
                    dueDate: record.dueDate,
                    isPinned: record.isPinned,
                    archivedAt: record.archivedAt,
                    trashedAt: record.trashedAt,
                    sortOrder: record.sortOrder,
                    origin: record.origin,
                    source: record.source,
                    list: record.listID.flatMap { listMapping[$0] },
                    tags: mappedTags,
                    attachments: attachments,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(item)
                itemsByID[chosenItemID] = item
                importedCount += 1
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            storedRelativePaths.forEach { try? attachmentStore.remove(relativePath: $0) }
            throw error
        }

        return CapturePackageImportResult(
            importedItemCount: importedCount,
            skippedDuplicateCount: duplicateCount,
            reassignedIdentifierCount: reassignedCount
        )
    }

    private func isExactDuplicate(
        _ record: CapturePackageManifest.ItemRecord,
        mappedTags: [CaptureTag],
        of item: CaptureItem
    ) -> Bool {
        let existingAttachments = item.attachments.sorted(by: { $0.order < $1.order })
        let recordAttachments = record.attachments.sorted(by: { $0.order < $1.order })
        let attachmentsMatch = recordAttachments.count == existingAttachments.count &&
            zip(recordAttachments, existingAttachments).allSatisfy { imported, existing in
                imported.id == existing.id &&
                    imported.kind == existing.kind &&
                    imported.typeIdentifier == existing.typeIdentifier &&
                    imported.originalFilename == existing.originalFilename &&
                    imported.url == existing.url &&
                    (imported.pageTitle == nil || imported.pageTitle == existing.pageTitle) &&
                    (imported.faviconPackagePath != nil) == (existing.faviconRelativePath != nil) &&
                    (imported.faviconTypeIdentifier == nil || imported.faviconTypeIdentifier == existing.faviconTypeIdentifier) &&
                    imported.order == existing.order
            }
        return record.text == item.text &&
            record.kind == item.kind &&
            record.isCompleted == item.isCompleted &&
            record.completedAt == item.completedAt &&
            record.dueDate == item.dueDate &&
            record.isPinned == item.isPinned &&
            record.archivedAt == item.archivedAt &&
            record.trashedAt == item.trashedAt &&
            record.origin == item.origin &&
            record.source == item.source &&
            record.listID == item.list?.id &&
            Set(mappedTags.map(\.id)) == Set(item.tags.map(\.id)) &&
            attachmentsMatch
    }

    private func validatedChild(path: String, of root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            throw CapturePackageError.unsafePath(path)
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let child = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard child.path.hasPrefix(rootPrefix), child.path != canonicalRoot.path else {
            throw CapturePackageError.unsafePath(path)
        }
        return child
    }

    private func sanitized(_ filename: String) -> String {
        filename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}

enum CapturePackageError: LocalizedError {
    case invalidExtension
    case destinationExists
    case invalidManifest(Error)
    case unsupportedSchema(Int)
    case unsafePath(String)
    case missingAttachment(String)
    case missingTag(UUID)
    case invalidTagName(String)

    var errorDescription: String? {
        switch self {
        case .invalidExtension: "Capture packages must use the .notchcapture extension."
        case .destinationExists: "A file already exists at the export destination."
        case let .invalidManifest(error): "The package manifest is invalid: \(error.localizedDescription)"
        case let .unsupportedSchema(version): "Package schema version \(version) is not supported."
        case let .unsafePath(path): "The package contains an unsafe path: \(path)"
        case let .missingAttachment(path): "The package attachment is missing: \(path)"
        case let .missingTag(id): "The package references a missing tag: \(id.uuidString)"
        case let .invalidTagName(name): "The package contains an invalid tag name: \(name)"
        }
    }
}
