import Foundation
import SwiftData

/// The on-disk schema used before Quick Snippets were removed. These private
/// models deliberately retain the original entity names so SwiftData can open
/// existing libraries long enough to remove their snippet-only records.
enum NotchCaptureSchemaV1: VersionedSchema {
    @Model
    final class CaptureItem {
        @Attribute(.unique) var id: UUID
        var text: String
        var kindRawValue: String
        var isCompleted: Bool
        var completedAt: Date?
        var dueDate: Date?
        var isPinned: Bool
        var archivedAt: Date?
        var trashedAt: Date?
        var sortOrder: Int?
        var createdAt: Date
        var updatedAt: Date
        var originRawValue: String
        var sourceApplicationName: String?
        var sourceBundleIdentifier: String?
        var sourceDocumentURL: URL?
        var reusableAt: Date?
        var lastCopiedAt: Date?
        var list: ItemList?
        var snippetCategory: SnippetCategory?
        @Relationship(deleteRule: .nullify, inverse: \CaptureTag.items)
        var tags: [CaptureTag]
        @Relationship(deleteRule: .cascade, inverse: \Attachment.item)
        var attachments: [Attachment]

        init(
            id: UUID = UUID(),
            text: String = "",
            kindRawValue: String = CaptureItemKind.note.rawValue,
            isCompleted: Bool = false,
            completedAt: Date? = nil,
            dueDate: Date? = nil,
            isPinned: Bool = false,
            archivedAt: Date? = nil,
            trashedAt: Date? = nil,
            sortOrder: Int? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            originRawValue: String = CaptureOrigin.manual.rawValue,
            sourceApplicationName: String? = nil,
            sourceBundleIdentifier: String? = nil,
            sourceDocumentURL: URL? = nil,
            reusableAt: Date? = nil,
            lastCopiedAt: Date? = nil,
            list: ItemList? = nil,
            snippetCategory: SnippetCategory? = nil,
            tags: [CaptureTag] = [],
            attachments: [Attachment] = []
        ) {
            self.id = id
            self.text = text
            self.kindRawValue = kindRawValue
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.dueDate = dueDate
            self.isPinned = isPinned
            self.archivedAt = archivedAt
            self.trashedAt = trashedAt
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.originRawValue = originRawValue
            self.sourceApplicationName = sourceApplicationName
            self.sourceBundleIdentifier = sourceBundleIdentifier
            self.sourceDocumentURL = sourceDocumentURL
            self.reusableAt = reusableAt
            self.lastCopiedAt = lastCopiedAt
            self.list = list
            self.snippetCategory = snippetCategory
            self.tags = tags
            self.attachments = attachments
        }
    }

    @Model
    final class SnippetCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        @Attribute(.unique) var normalizedName: String
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \CaptureItem.snippetCategory)
        var items: [CaptureItem]

        init(
            id: UUID = UUID(),
            name: String,
            normalizedName: String,
            sortOrder: Int = 0,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            items: [CaptureItem] = []
        ) {
            self.id = id
            self.name = name
            self.normalizedName = normalizedName
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.items = items
        }
    }

    @Model
    final class CaptureTag {
        @Attribute(.unique) var id: UUID
        var name: String
        @Attribute(.unique) var normalizedName: String
        var colorSeed: Double?
        var createdAt: Date
        var updatedAt: Date
        var items: [CaptureItem]

        init(
            id: UUID = UUID(),
            name: String,
            normalizedName: String,
            colorSeed: Double? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            items: [CaptureItem] = []
        ) {
            self.id = id
            self.name = name
            self.normalizedName = normalizedName
            self.colorSeed = colorSeed
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.items = items
        }
    }

    @Model
    final class ItemList {
        @Attribute(.unique) var id: UUID
        var name: String
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \CaptureItem.list)
        var items: [CaptureItem]

        init(
            id: UUID = UUID(),
            name: String,
            sortOrder: Int = 0,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            items: [CaptureItem] = []
        ) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.items = items
        }
    }

    @Model
    final class Attachment {
        @Attribute(.unique) var id: UUID
        var kindRawValue: String
        var typeIdentifier: String
        var originalFilename: String
        var relativePath: String?
        var url: URL?
        var pageTitle: String?
        var faviconRelativePath: String?
        var faviconTypeIdentifier: String?
        var order: Int
        var createdAt: Date
        var item: CaptureItem?

        init(
            id: UUID = UUID(),
            kindRawValue: String,
            typeIdentifier: String,
            originalFilename: String,
            relativePath: String? = nil,
            url: URL? = nil,
            pageTitle: String? = nil,
            faviconRelativePath: String? = nil,
            faviconTypeIdentifier: String? = nil,
            order: Int = 0,
            createdAt: Date = .now,
            item: CaptureItem? = nil
        ) {
            self.id = id
            self.kindRawValue = kindRawValue
            self.typeIdentifier = typeIdentifier
            self.originalFilename = originalFilename
            self.relativePath = relativePath
            self.url = url
            self.pageTitle = pageTitle
            self.faviconRelativePath = faviconRelativePath
            self.faviconTypeIdentifier = faviconTypeIdentifier
            self.order = order
            self.createdAt = createdAt
            self.item = item
        }
    }

    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        CaptureItem.self,
        CaptureTag.self,
        ItemList.self,
        SnippetCategory.self,
        Attachment.self,
    ]
}

enum NotchCaptureSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] = [
        CaptureItem.self,
        CaptureTag.self,
        ItemList.self,
        Attachment.self,
    ]
}

enum NotchCaptureMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        NotchCaptureSchemaV1.self,
        NotchCaptureSchemaV2.self,
    ]

    static let stages: [MigrationStage] = [
        .custom(
            fromVersion: NotchCaptureSchemaV1.self,
            toVersion: NotchCaptureSchemaV2.self,
            willMigrate: { context in
                let captures = try context.fetch(
                    FetchDescriptor<NotchCaptureSchemaV1.CaptureItem>()
                )
                for capture in captures where capture.reusableAt != nil {
                    context.delete(capture)
                }
                let categories = try context.fetch(
                    FetchDescriptor<NotchCaptureSchemaV1.SnippetCategory>()
                )
                for category in categories {
                    context.delete(category)
                }
                try context.save()
            },
            didMigrate: nil
        ),
    ]
}
