import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ImageAttachmentPayload: Sendable, Equatable {
    let data: Data
    let typeIdentifier: String
    let filename: String
}

@MainActor
final class ItemRepository {
    let modelContext: ModelContext
    private let attachmentStore: AttachmentStore?

    init(modelContext: ModelContext, attachmentStore: AttachmentStore? = nil) {
        self.modelContext = modelContext
        self.attachmentStore = attachmentStore
    }

    @discardableResult
    func createItem(
        text: String = "",
        origin: CaptureOrigin,
        source: CaptureSource = CaptureSource(),
        list: ItemList? = nil,
        tagNames: [String] = [],
        attachments: [Attachment] = [],
        now: Date = .now
    ) throws -> CaptureItem {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            throw ItemRepositoryError.emptyCapture
        }
        do {
            let tags = try resolveTags(named: tagNames, now: now)
            let item = CaptureItem(
                text: text,
                sortOrder: try nextBottomSortOrder(isPinned: false, list: list),
                origin: origin,
                source: source,
                list: list,
                tags: tags,
                attachments: attachments,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(item)
            try modelContext.save()
            return item
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    func createItem(
        text: String,
        origin: CaptureOrigin,
        list: ItemList? = nil,
        tagNames: [String] = [],
        imageAttachments: [ImageAttachmentPayload],
        now: Date = .now
    ) throws -> CaptureItem {
        guard let attachmentStore else { throw ItemRepositoryError.attachmentStoreRequired }
        var storedPaths: [String] = []

        do {
            let attachments = try imageAttachments.enumerated().map { order, image in
                let type = UTType(image.typeIdentifier) ?? .data
                let stored = try attachmentStore.storeData(
                    image.data,
                    filename: image.filename,
                    type: type,
                    kind: .image
                )
                storedPaths.append(stored.relativePath)
                return attachment(from: stored, order: order)
            }
            return try createItem(
                text: text,
                origin: origin,
                list: list,
                tagNames: tagNames,
                attachments: attachments,
                now: now
            )
        } catch {
            storedPaths.forEach { try? attachmentStore.remove(relativePath: $0) }
            throw error
        }
    }

    @discardableResult
    func createItem(
        from payload: CapturePayload,
        origin: CaptureOrigin,
        source: CaptureSource = CaptureSource(),
        list: ItemList? = nil,
        tagNames: [String] = [],
        now: Date = .now
    ) throws -> CaptureItem {
        guard !payload.isEmpty else { throw ItemRepositoryError.emptyCapture }
        var text = ""
        var attachments: [Attachment] = []
        var storedPaths: [String] = []

        do {
            switch payload {
            case let .text(value):
                text = value
            case let .url(url):
                attachments = [urlAttachment(url, order: 0)]
            case let .files(urls):
                guard let attachmentStore else { throw ItemRepositoryError.attachmentStoreRequired }
                for (order, url) in urls.enumerated() {
                    let stored = try attachmentStore.storeFile(at: url)
                    storedPaths.append(stored.relativePath)
                    attachments.append(attachment(from: stored, order: order))
                }
            case let .image(data, typeIdentifier):
                guard let attachmentStore else { throw ItemRepositoryError.attachmentStoreRequired }
                let type = UTType(typeIdentifier) ?? .data
                let filename = "Capture.\(type.preferredFilenameExtension ?? "data")"
                let stored = try attachmentStore.storeData(
                    data,
                    filename: filename,
                    type: type,
                    kind: origin == .screenshot ? .screenshot : .image
                )
                storedPaths.append(stored.relativePath)
                attachments = [attachment(from: stored, order: 0)]
            case let .mixed(value, urls):
                text = value ?? ""
                attachments = urls.enumerated().map { urlAttachment($0.element, order: $0.offset) }
            }
            return try createItem(
                text: text,
                origin: origin,
                source: source,
                list: list,
                tagNames: tagNames,
                attachments: attachments,
                now: now
            )
        } catch {
            storedPaths.forEach { try? attachmentStore?.remove(relativePath: $0) }
            throw error
        }
    }

    @discardableResult
    func createItem(from selection: SelectionCaptureResult, now: Date = .now) throws -> CaptureItem {
        try createItem(from: selection.payload, origin: .selection, source: selection.source, now: now)
    }

    func fetchTags() throws -> [CaptureTag] {
        try modelContext.fetch(FetchDescriptor<CaptureTag>()).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func backfillMissingTagColorSeeds() throws -> Bool {
        let tags = try modelContext.fetch(FetchDescriptor<CaptureTag>())
        let missing = tags.filter { $0.colorSeed == nil }
        guard !missing.isEmpty else { return false }
        for tag in missing {
            tag.colorSeed = TagColorSeed.random()
            tag.updatedAt = .now
        }
        try modelContext.save()
        return true
    }

    @discardableResult
    func createTag(name proposedName: String, now: Date = .now) throws -> CaptureTag {
        let name = CaptureTagParser.normalizedDisplayName(proposedName)
        let normalized = CaptureTagParser.normalize(name)
        guard !name.isEmpty, name.allSatisfy(CaptureTagParser.isTagCharacter) else {
            throw ItemRepositoryError.invalidTagName
        }
        if let existing = try fetchTags().first(where: { $0.normalizedName == normalized }) {
            return existing
        }
        let tag = CaptureTag(name: name, normalizedName: normalized, createdAt: now, updatedAt: now)
        modelContext.insert(tag)
        try modelContext.save()
        return tag
    }

    /// Renames a tag, merging it into an existing tag when normalized names collide.
    @discardableResult
    func renameTag(_ tag: CaptureTag, to proposedName: String, now: Date = .now) throws -> CaptureTag {
        let name = CaptureTagParser.normalizedDisplayName(proposedName)
        let normalized = CaptureTagParser.normalize(name)
        guard !name.isEmpty, name.allSatisfy(CaptureTagParser.isTagCharacter) else {
            throw ItemRepositoryError.invalidTagName
        }
        do {
            let originalName = tag.name
            let linkedItems = Array(tag.items)
            if let destination = try fetchTags().first(where: {
                $0.id != tag.id && $0.normalizedName == normalized
            }) {
                for item in linkedItems {
                    item.text = CaptureTagParser.replacingTagMentions(
                        in: item.text,
                        matching: originalName,
                        with: destination.name
                    )
                    if !item.tags.contains(where: { $0.id == destination.id }) {
                        item.tags.append(destination)
                    }
                    item.touch(at: now)
                }
                modelContext.delete(tag)
                destination.updatedAt = now
                try modelContext.save()
                return destination
            }
            for item in linkedItems {
                item.text = CaptureTagParser.replacingTagMentions(
                    in: item.text,
                    matching: originalName,
                    with: name
                )
                item.touch(at: now)
            }
            tag.name = name
            tag.normalizedName = normalized
            tag.updatedAt = now
            try modelContext.save()
            return tag
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deleteTag(_ tag: CaptureTag, now: Date = .now) throws {
        for item in tag.items {
            item.tags.removeAll { $0.id == tag.id }
            item.touch(at: now)
        }
        modelContext.delete(tag)
        try modelContext.save()
    }

    @discardableResult
    func createList(name: String) throws -> ItemList {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ItemRepositoryError.emptyListName }
        let descriptor = FetchDescriptor<ItemList>(sortBy: [SortDescriptor(\ItemList.sortOrder)])
        let lists = try modelContext.fetch(descriptor)
        guard !lists.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw ItemRepositoryError.duplicateListName
        }
        let nextOrder = (lists.map(\.sortOrder).max() ?? -1) + 1
        let list = ItemList(name: trimmed, sortOrder: nextOrder)
        modelContext.insert(list)
        try modelContext.save()
        return list
    }

    func renameList(_ list: ItemList, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ItemRepositoryError.emptyListName }
        let lists = try modelContext.fetch(FetchDescriptor<ItemList>())
        guard !lists.contains(where: {
            $0.id != list.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            throw ItemRepositoryError.duplicateListName
        }
        list.name = trimmed
        list.updatedAt = .now
        try modelContext.save()
    }

    /// Deletes the folder but returns every contained item to Inbox.
    @discardableResult
    func deleteList(_ list: ItemList) throws -> Int {
        let containedItems = list.items
        do {
            for isPinned in [true, false] {
                let ordered = containedItems
                    .filter { $0.isPinned == isPinned }
                    .sorted(by: migrationComesBefore)
                let inboxTop = try nextTopSortOrder(isPinned: isPinned, list: nil)
                for (index, item) in ordered.enumerated() {
                    item.list = nil
                    item.sortOrder = inboxTop - ordered.count + index
                }
            }
            modelContext.delete(list)
            try modelContext.save()
            return containedItems.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func fetch(scope: CaptureScope, search: String = "", now: Date = .now) throws -> [CaptureItem] {
        let descriptor = FetchDescriptor<CaptureItem>(
            sortBy: [SortDescriptor(\CaptureItem.updatedAt, order: .reverse)]
        )
        let query = CaptureTagParser.parse(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let matching = try modelContext.fetch(descriptor).filter { item in
            let belongs: Bool
            switch scope {
            case .inbox:
                belongs = !item.isArchived && !item.isTrashed && (
                    !item.isCompleted || item.completedAt.map {
                        CompletionVisibility.remainsOnMainPage(completedAt: $0, now: now)
                    } == true
                )
            case .tasks:
                belongs = item.kind == .task && !item.isCompleted && !item.isArchived && !item.isTrashed
            case .due:
                belongs = item.kind == .task && item.dueDate != nil && !item.isCompleted && !item.isArchived && !item.isTrashed
            case .completed:
                belongs = item.kind == .task && item.isCompleted && !item.isTrashed
            case .archive:
                belongs = item.isArchived && !item.isTrashed
            case .trash:
                belongs = item.isTrashed
            case let .list(id):
                belongs = item.list?.id == id && !item.isArchived && !item.isTrashed
            }
            let searchableText = CaptureTagParser.removingTagMentions(
                in: item.text,
                matching: item.tags.map(\.name)
            )
            let textMatches = query.text.isEmpty ||
                searchableText.localizedCaseInsensitiveContains(query.text) ||
                item.attachments.contains {
                    $0.originalFilename.localizedCaseInsensitiveContains(query.text)
                }
            let requestedTags = Set(query.tagNames.map(CaptureTagParser.normalize))
            let tagMatches = requestedTags.isEmpty || item.tags.contains {
                requestedTags.contains($0.normalizedName)
            }
            return belongs && textMatches && tagMatches
        }
        return matching.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return comesBefore($0, $1)
        }
    }

    /// Gives legacy/imported rows stable ranks while preserving any existing custom order.
    @discardableResult
    func backfillMissingSortOrders() throws -> Bool {
        let items = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        let needsBackfill = items.contains { $0.sortOrder == nil }
        let grouped = Dictionary(grouping: items) { item in
            OrderGroup(listID: item.list?.id, isPinned: item.isPinned)
        }
        let hasDuplicateRanks = grouped.values.contains { group in
            let ranks = group.compactMap(\.sortOrder)
            return Set(ranks).count != ranks.count
        }
        guard needsBackfill || hasDuplicateRanks else { return false }

        for group in grouped.values {
            let ordered = group.sorted(by: migrationComesBefore)
            for (index, item) in ordered.enumerated() {
                item.sortOrder = index
            }
        }
        try modelContext.save()
        return true
    }

    func updateText(_ item: CaptureItem, text: String, now: Date = .now) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !item.attachments.isEmpty else {
            throw ItemRepositoryError.emptyCapture
        }
        do {
            let parsed = CaptureTagParser.parse(text)
            item.text = text
            item.tags = try resolveTags(named: parsed.tagNames, now: now)
            item.touch(at: now)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func setKind(_ kind: CaptureItemKind, for item: CaptureItem) throws {
        item.kind = kind
        try modelContext.save()
    }

    func setCompleted(_ completed: Bool, for item: CaptureItem, at date: Date = .now) throws {
        guard item.kind == .task else { throw ItemRepositoryError.notATask }
        item.isCompleted = completed
        item.completedAt = completed ? date : nil
        item.touch(at: date)
        try modelContext.save()
    }

    func setDueDate(_ date: Date?, for item: CaptureItem, calendar: Calendar = .current) throws {
        item.kind = .task
        item.dueDate = date.map { calendar.startOfDay(for: $0) }
        item.touch()
        try modelContext.save()
    }

    func move(_ item: CaptureItem, to list: ItemList?) throws {
        guard item.list?.id != list?.id else { return }
        item.sortOrder = try nextTopSortOrder(isPinned: item.isPinned, list: list)
        item.list = list
        item.touch()
        try modelContext.save()
    }

    func setPinned(_ pinned: Bool, for item: CaptureItem) throws {
        guard item.isPinned != pinned else { return }
        item.sortOrder = try nextTopSortOrder(isPinned: pinned, list: item.list)
        item.isPinned = pinned
        item.touch()
        try modelContext.save()
    }

    func applyOrderAssignments(_ assignments: [ItemOrderAssignment]) throws {
        guard !assignments.isEmpty else { return }
        let items = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        if let missing = assignments.first(where: { byID[$0.id] == nil }) {
            throw ItemRepositoryError.itemNotFound(missing.id)
        }
        do {
            for assignment in assignments {
                guard let item = byID[assignment.id] else { continue }
                item.isPinned = assignment.isPinned
                item.sortOrder = assignment.sortOrder
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func archive(_ item: CaptureItem, at date: Date = .now) throws {
        item.archivedAt = date
        item.trashedAt = nil
        item.touch(at: date)
        try modelContext.save()
    }

    func trash(_ item: CaptureItem, at date: Date = .now) throws {
        item.trashedAt = date
        item.touch(at: date)
        try modelContext.save()
    }

    func restore(_ item: CaptureItem) throws {
        item.archivedAt = nil
        item.trashedAt = nil
        item.touch()
        try modelContext.save()
    }

    func deletePermanently(_ item: CaptureItem) throws {
        let storedPaths = item.attachments.compactMap(\.relativePath)
        modelContext.delete(item)
        try modelContext.save()
        try storedPaths.forEach { try attachmentStore?.remove(relativePath: $0) }
    }

    @discardableResult
    func emptyTrash() throws -> Int {
        let items = try fetch(scope: .trash)
        let storedPaths = items.flatMap(\.attachments).compactMap(\.relativePath)
        items.forEach(modelContext.delete)
        try modelContext.save()
        try storedPaths.forEach { try attachmentStore?.remove(relativePath: $0) }
        return items.count
    }

    private func attachment(from stored: StoredAttachment, order: Int) -> Attachment {
        Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath,
            order: order
        )
    }

    private func urlAttachment(_ url: URL, order: Int) -> Attachment {
        Attachment(
            kind: .url,
            typeIdentifier: UTType.url.identifier,
            originalFilename: url.host ?? url.absoluteString,
            url: url,
            order: order
        )
    }

    private func nextTopSortOrder(isPinned: Bool, list: ItemList?) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        return (items.filter {
            $0.isPinned == isPinned && $0.list?.id == list?.id
        }.compactMap(\.sortOrder).min() ?? 0) - 1
    }

    /// Assigns the next rank so a newly created item stacks below existing ones.
    private func nextBottomSortOrder(isPinned: Bool, list: ItemList?) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<CaptureItem>())
        return (items.filter {
            $0.isPinned == isPinned && $0.list?.id == list?.id
        }.compactMap(\.sortOrder).max() ?? -1) + 1
    }

    private func resolveTags(named proposedNames: [String], now: Date) throws -> [CaptureTag] {
        let existing = try modelContext.fetch(FetchDescriptor<CaptureTag>())
        var byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.normalizedName, $0) })
        var result: [CaptureTag] = []
        for proposedName in proposedNames {
            let name = CaptureTagParser.normalizedDisplayName(proposedName)
            let normalized = CaptureTagParser.normalize(name)
            guard !name.isEmpty, name.allSatisfy(CaptureTagParser.isTagCharacter) else {
                throw ItemRepositoryError.invalidTagName
            }
            let tag: CaptureTag
            if let found = byName[normalized] {
                tag = found
            } else {
                let created = CaptureTag(
                    name: name,
                    normalizedName: normalized,
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(created)
                byName[normalized] = created
                tag = created
            }
            if !result.contains(where: { $0.normalizedName == normalized }) {
                result.append(tag)
            }
        }
        return result
    }

    private func comesBefore(_ lhs: CaptureItem, _ rhs: CaptureItem) -> Bool {
        switch (lhs.sortOrder, rhs.sortOrder) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return false
        case (nil, _?):
            return true
        default:
            let leftDate = lhs.completedAt ?? lhs.createdAt
            let rightDate = rhs.completedAt ?? rhs.createdAt
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func migrationComesBefore(_ lhs: CaptureItem, _ rhs: CaptureItem) -> Bool {
        switch (lhs.sortOrder, rhs.sortOrder) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        default:
            let leftDate = lhs.completedAt ?? lhs.createdAt
            let rightDate = rhs.completedAt ?? rhs.createdAt
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private struct OrderGroup: Hashable {
        let listID: UUID?
        let isPinned: Bool
    }
}

enum ItemRepositoryError: LocalizedError {
    case emptyCapture
    case emptyListName
    case duplicateListName
    case notATask
    case attachmentStoreRequired
    case itemNotFound(UUID)
    case listNotFound(UUID)
    case tagNotFound(UUID)
    case invalidTagName

    var errorDescription: String? {
        switch self {
        case .emptyCapture: "A capture must contain text or an attachment."
        case .emptyListName: "A folder name cannot be empty."
        case .duplicateListName: "A folder with that name already exists."
        case .notATask: "Only tasks can be completed."
        case .attachmentStoreRequired: "An attachment store is required for file and image captures."
        case let .itemNotFound(id): "The item \(id.uuidString) no longer exists."
        case let .listNotFound(id): "The folder \(id.uuidString) no longer exists."
        case let .tagNotFound(id): "The tag \(id.uuidString) no longer exists."
        case .invalidTagName: "Tag names can contain letters, numbers, hyphens, and underscores."
        }
    }
}
