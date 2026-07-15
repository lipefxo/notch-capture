import Foundation
import SwiftData
import UniformTypeIdentifiers

enum CaptureItemKind: String, Codable, CaseIterable, Sendable {
    case note
    case task
}

enum CaptureOrigin: String, Codable, CaseIterable, Sendable {
    case selection
    case manual
    case drop
    case screenshot
    case imported
}

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case file
    case image
    case url
    case screenshot
}

enum CaptureScope: Hashable, Sendable {
    case inbox
    case tasks
    case due
    case completed
    case archive
    case trash
    case list(UUID)
}

enum CompletionVisibility {
    static let mainPageRetention: TimeInterval = 24 * 60 * 60

    static func remainsOnMainPage(completedAt: Date, now: Date = .now) -> Bool {
        completedAt.addingTimeInterval(mainPageRetention) > now
    }
}

enum CaptureRequest: Sendable {
    case selection
    case manual(String)
    case drop([URL])
    case screenshot
    case importPackage(URL)
}

enum CapturePayload: Sendable, Equatable {
    case text(String)
    case url(URL)
    case files([URL])
    case image(Data, typeIdentifier: String)
    case mixed(text: String?, urls: [URL])

    var isEmpty: Bool {
        switch self {
        case let .text(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url:
            return false
        case let .files(urls):
            return urls.isEmpty
        case let .image(data, _):
            return data.isEmpty
        case let .mixed(text, urls):
            return (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && urls.isEmpty
        }
    }
}

struct CaptureSource: Codable, Equatable, Sendable {
    var applicationName: String?
    var bundleIdentifier: String?
    var documentURL: URL?

    init(applicationName: String? = nil, bundleIdentifier: String? = nil, documentURL: URL? = nil) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.documentURL = documentURL
    }
}

struct SelectionCaptureResult: Equatable, Sendable {
    let payload: CapturePayload
    let source: CaptureSource
    let usedPasteboardFallback: Bool
}

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
    var createdAt: Date
    var updatedAt: Date
    var originRawValue: String
    var sourceApplicationName: String?
    var sourceBundleIdentifier: String?
    var sourceDocumentURL: URL?
    var list: ItemList?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.item)
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        text: String = "",
        kind: CaptureItemKind = .note,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        dueDate: Date? = nil,
        isPinned: Bool = false,
        archivedAt: Date? = nil,
        trashedAt: Date? = nil,
        origin: CaptureOrigin = .manual,
        source: CaptureSource = CaptureSource(),
        list: ItemList? = nil,
        attachments: [Attachment] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.kindRawValue = kind.rawValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.dueDate = dueDate
        self.isPinned = isPinned
        self.archivedAt = archivedAt
        self.trashedAt = trashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originRawValue = origin.rawValue
        self.sourceApplicationName = source.applicationName
        self.sourceBundleIdentifier = source.bundleIdentifier
        self.sourceDocumentURL = source.documentURL
        self.list = list
        self.attachments = attachments
        for attachment in attachments {
            attachment.item = self
        }
    }

    var kind: CaptureItemKind {
        get { CaptureItemKind(rawValue: kindRawValue) ?? .note }
        set {
            kindRawValue = newValue.rawValue
            if newValue == .note {
                isCompleted = false
                completedAt = nil
            }
            touch()
        }
    }

    var origin: CaptureOrigin {
        get { CaptureOrigin(rawValue: originRawValue) ?? .manual }
        set { originRawValue = newValue.rawValue; touch() }
    }

    var source: CaptureSource {
        get {
            CaptureSource(
                applicationName: sourceApplicationName,
                bundleIdentifier: sourceBundleIdentifier,
                documentURL: sourceDocumentURL
            )
        }
        set {
            sourceApplicationName = newValue.applicationName
            sourceBundleIdentifier = newValue.bundleIdentifier
            sourceDocumentURL = newValue.documentURL
            touch()
        }
    }

    var displayTitle: String {
        if let firstLine = text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return attachments.sorted(by: { $0.order < $1.order }).first?.originalFilename ?? "Untitled capture"
    }

    var isArchived: Bool { archivedAt != nil }
    var isTrashed: Bool { trashedAt != nil }

    func touch(at date: Date = .now) {
        updatedAt = date
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
    var order: Int
    var createdAt: Date
    var item: CaptureItem?

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        typeIdentifier: String,
        originalFilename: String,
        relativePath: String? = nil,
        url: URL? = nil,
        order: Int = 0,
        createdAt: Date = .now,
        item: CaptureItem? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.typeIdentifier = typeIdentifier
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.url = url
        self.order = order
        self.createdAt = createdAt
        self.item = item
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRawValue) ?? .file }
        set { kindRawValue = newValue.rawValue }
    }

    var contentType: UTType? { UTType(typeIdentifier) }
}
