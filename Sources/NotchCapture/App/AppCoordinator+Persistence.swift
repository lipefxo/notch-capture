import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

private struct UndoLedgerStatusState {
    let item: CaptureItem
    let archivedAt: Date?
    let trashedAt: Date?
    let updatedAt: Date
}

extension AppCoordinator {
    func presentConfirmation(for item: CaptureItem) {
        presentCaptureFeedback(for: item, feedback: .transientConfirmation)
    }

    func presentCaptureFeedback(
        for item: CaptureItem,
        feedback: AppViewModel.CaptureFeedback
    ) {
        reloadFromStore()
        scheduleLinkMetadataFetches(for: item)
        guard let ledger = viewModel.items.first(where: { $0.id == item.id }) else { return }
        let refreshesVisibleConfirmation = feedback == .transientConfirmation
            && viewModel.surfaceState == .confirmation
        viewModel.showCaptureFeedback(for: ledger, feedback: feedback)
        if refreshesVisibleConfirmation {
            panelController.restartConfirmationDismissal()
        }
    }

    /// Metadata retrieval is intentionally detached from capture confirmation:
    /// a link is already durable and visible before any request begins.
    private func scheduleLinkMetadataFetches(for item: CaptureItem) {
        let requests = item.attachments.compactMap { attachment -> (UUID, URL)? in
            guard attachment.kind == .url,
                  attachment.pageTitle == nil || attachment.faviconRelativePath == nil,
                  let url = attachment.url else {
                return nil
            }
            return (attachment.id, url)
        }
        for (attachmentID, pageURL) in requests {
            let fetcher = linkMetadataFetcher
            Task { [weak self] in
                guard let metadata = await fetcher.fetchMetadata(for: pageURL) else { return }
                guard let self else { return }
                if let title = metadata.title {
                    self.persist(pageTitle: title, forAttachmentID: attachmentID)
                }
                if let favicon = metadata.favicon {
                    self.persist(favicon: favicon, forAttachmentID: attachmentID)
                }
            }
        }
    }

    private func persist(pageTitle: String, forAttachmentID attachmentID: UUID) {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == attachmentID })
        descriptor.fetchLimit = 1
        guard let attachment = try? modelContainer.mainContext.fetch(descriptor).first,
              attachment.kind == .url,
              attachment.pageTitle == nil else {
            return
        }

        do {
            attachment.pageTitle = pageTitle
            try modelContainer.mainContext.save()
            if let itemID = attachment.item?.id {
                reloadItem(itemID)
            }
        } catch {
            modelContainer.mainContext.rollback()
        }
    }

    private func persist(favicon: FaviconData, forAttachmentID attachmentID: UUID) {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == attachmentID })
        descriptor.fetchLimit = 1
        guard let attachment = try? modelContainer.mainContext.fetch(descriptor).first,
              attachment.kind == .url,
              attachment.faviconRelativePath == nil else {
            return
        }

        var storedPath: String?
        do {
            let type = UTType(favicon.typeIdentifier) ?? .png
            let stored = try attachmentStore.storeData(
                favicon.data,
                filename: favicon.filename,
                type: type,
                id: UUID(),
                kind: .image
            )
            storedPath = stored.relativePath
            attachment.faviconRelativePath = stored.relativePath
            attachment.faviconTypeIdentifier = favicon.typeIdentifier
            try modelContainer.mainContext.save()
            if let itemID = attachment.item?.id {
                reloadItem(itemID)
            }
        } catch {
            modelContainer.mainContext.rollback()
            if let storedPath {
                try? attachmentStore.remove(relativePath: storedPath)
            }
        }
    }

    func undoCapture(id: UUID?) -> String? {
        guard let id else { return nil }
        guard let item = findItem(id) else {
            return ItemRepositoryError.itemNotFound(id).localizedDescription
        }
        do {
            // Trash, not permanent delete: a mis-click on the confirmation toast
            // must never destroy a capture (or its attachment files).
            try repository.trash(item)
            reloadItem(id)
            return nil
        } catch {
            reloadFromStore()
            return error.localizedDescription
        }
    }

    func toggleComplete(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            if item.kind == .note { try repository.setKind(.task, for: item) }
            try repository.setCompleted(!item.isCompleted, for: item)
            reloadItem(id)
        } catch { show(error) }
    }

    func updateText(_ text: String, for id: UUID) -> String? {
        guard let item = findItem(id) else {
            return ItemRepositoryError.itemNotFound(id).localizedDescription
        }
        do {
            try repository.updateText(item, text: text)
            reloadFromStore()
            return nil
        } catch {
            reloadFromStore()
            return error.localizedDescription
        }
    }

    func togglePin(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.setPinned(!item.isPinned, for: item)
            reloadItem(id)
        } catch { show(error) }
    }

    func applyOrderAssignments(_ assignments: [ItemOrderAssignment]) {
        do {
            try repository.applyOrderAssignments(assignments)
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func applyFolderOrderAssignments(_ assignments: [FolderOrderAssignment]) {
        do {
            try repository.applyFolderOrderAssignments(assignments)
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func archive(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.archive(item)
            reloadItem(id)
        } catch {
            reloadFromStore()
            viewModel.discardPendingLedgerUndo(for: id)
            show(error)
        }
    }

    func setDueDate(_ date: Date?, for id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.setDueDate(date, for: item)
            reloadItem(id)
        } catch { show(error) }
    }

    func move(id: UUID, to folderID: UUID?) {
        guard let item = findItem(id) else { return }
        do {
            let list = try folderID.map(findList)
            try repository.move(item, to: list)
            reloadItem(id)
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func createFolder(named name: String) -> UUID? {
        do {
            let list = try repository.createList(name: name)
            reloadFromStore()
            return list.id
        } catch { show(error) }
        return nil
    }

    func renameFolder(id: UUID, to name: String) {
        do {
            try repository.renameList(try findList(id), to: name)
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func deleteFolder(id: UUID) {
        do {
            _ = try repository.deleteList(try findList(id))
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func createTag(named name: String) {
        do {
            _ = try repository.createTag(name: name)
            reloadFromStore()
        } catch { show(error) }
    }

    func renameTag(id: UUID, to name: String) {
        do {
            _ = try repository.renameTag(try findTag(id), to: name)
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func deleteTag(id: UUID) {
        do {
            try repository.deleteTag(try findTag(id))
            reloadFromStore()
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func trash(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.trash(item)
            reloadItem(id)
        } catch {
            reloadFromStore()
            viewModel.discardPendingLedgerUndo(for: id)
            show(error)
        }
    }

    func restore(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.restore(item)
            reloadItem(id)
        } catch {
            reloadFromStore()
            show(error)
        }
    }

    func deletePermanently(id: UUID) {
        guard let item = findItem(id) else { return }
        do {
            try repository.deletePermanently(item)
            reloadFromStore()
        } catch {
            // The row is removed optimistically before this hook. Reload the
            // rollback-restored model before showing the failure so Trash does
            // not falsely appear empty.
            reloadFromStore()
            show(error)
        }
    }

    /// Applies the latest view-model undo as a status-only persistence
    /// transaction. Replaying a complete `LedgerItem` would overwrite text,
    /// folder, tags, or ordering edits made after the original action, so the
    /// operation carries only the archive/trash bits it owns.
    func undoLedgerAction(_ action: AppViewModel.LedgerUndoAction) -> String? {
        var previousStates: [UUID: UndoLedgerStatusState] = [:]
        do {
            switch action {
            case let .archive(snapshot):
                guard let item = findItem(snapshot.id) else {
                    throw ItemRepositoryError.itemNotFound(snapshot.id)
                }
                guard item.isArchived == snapshot.resultingIsArchived,
                      item.isTrashed == snapshot.resultingIsTrashed else {
                    // A later status decision superseded this undo. Consume it
                    // without touching the newer state.
                    return nil
                }
                previousStates[item.id] = UndoLedgerStatusState(
                    item: item,
                    archivedAt: item.archivedAt,
                    trashedAt: item.trashedAt,
                    updatedAt: item.updatedAt
                )
                item.archivedAt = snapshot.isArchived ? item.archivedAt ?? .now : nil
                item.trashedAt = snapshot.isTrashed ? item.trashedAt ?? .now : nil
                item.touch()
            case let .trash(snapshot):
                guard let item = findItem(snapshot.id) else {
                    throw ItemRepositoryError.itemNotFound(snapshot.id)
                }
                guard item.isTrashed == snapshot.resultingIsTrashed else { return nil }
                previousStates[item.id] = UndoLedgerStatusState(
                    item: item,
                    archivedAt: item.archivedAt,
                    trashedAt: item.trashedAt,
                    updatedAt: item.updatedAt
                )
                item.trashedAt = snapshot.isTrashed ? item.trashedAt ?? .now : nil
                item.touch()
            case let .clear(snapshots):
                for snapshot in snapshots {
                    guard let item = findItem(snapshot.id) else { continue }
                    guard item.isTrashed == snapshot.resultingIsTrashed else { continue }
                    previousStates[item.id] = UndoLedgerStatusState(
                        item: item,
                        archivedAt: item.archivedAt,
                        trashedAt: item.trashedAt,
                        updatedAt: item.updatedAt
                    )
                    item.trashedAt = snapshot.isTrashed ? item.trashedAt ?? .now : nil
                    item.touch()
                }
            }
            try modelContainer.mainContext.save()
            reloadFromStore()
            return nil
        } catch {
            // SwiftData may leave failed scalar writes on the registered
            // objects until rollback. Restore the pre-undo status and update
            // timestamp first so rollback cannot expose a stale half-undo to
            // the live view model.
            for state in previousStates.values {
                state.item.archivedAt = state.archivedAt
                state.item.trashedAt = state.trashedAt
                state.item.updatedAt = state.updatedAt
            }
            modelContainer.mainContext.rollback()
            reloadFromStore()
            return error.localizedDescription
        }
    }

    private func findItem(_ id: UUID) -> CaptureItem? {
        var descriptor = FetchDescriptor<CaptureItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    func findList(_ id: UUID) throws -> ItemList {
        let lists = try modelContainer.mainContext.fetch(FetchDescriptor<ItemList>())
        guard let list = lists.first(where: { $0.id == id }) else {
            throw ItemRepositoryError.listNotFound(id)
        }
        return list
    }

    private func findTag(_ id: UUID) throws -> CaptureTag {
        let tags = try modelContainer.mainContext.fetch(FetchDescriptor<CaptureTag>())
        guard let tag = tags.first(where: { $0.id == id }) else {
            throw ItemRepositoryError.tagNotFound(id)
        }
        return tag
    }

    /// Refreshes a single ledger row after a one-item mutation, avoiding the
    /// full-store fetch and whole-ledger rebuild of `reloadFromStore()`.
    private func reloadItem(_ id: UUID) {
        guard !previewMode else { return }
        guard let stored = findItem(id) else {
            viewModel.items.removeAll { $0.id == id }
            return
        }
        let ledger = makeLedgerItem(stored)
        if let index = viewModel.items.firstIndex(where: { $0.id == id }) {
            viewModel.items[index] = ledger
        } else {
            reloadFromStore()
        }
    }

    func reloadFromStore() {
        guard !previewMode else { return }
        do {
            let descriptor = FetchDescriptor<CaptureItem>(
                sortBy: [SortDescriptor(\CaptureItem.createdAt, order: .reverse)]
            )
            let items = try modelContainer.mainContext.fetch(descriptor)
            let lists = try modelContainer.mainContext.fetch(
                FetchDescriptor<ItemList>(sortBy: [SortDescriptor(\ItemList.sortOrder)])
            )
            let tags = try modelContainer.mainContext.fetch(FetchDescriptor<CaptureTag>())
            viewModel.items = items.map(makeLedgerItem)
            viewModel.folders = lists.map {
                AppViewModel.FolderSummary(id: $0.id, name: $0.name, sortOrder: $0.sortOrder)
            }
            viewModel.tags = tags.map {
                AppViewModel.TagSummary(
                    id: $0.id,
                    name: $0.name,
                    colorSeed: $0.colorSeed ?? TagColorSeed.stable(for: $0.id)
                )
            }
            viewModel.reconcileBrowsingLocation()
        } catch {
            show(error)
        }
    }

    private func makeLedgerItem(_ item: CaptureItem) -> AppViewModel.LedgerItem {
        let lines = item.text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let detail = lines.dropFirst().joined(separator: "\n")
        let attachments = item.attachments.sorted { $0.order < $1.order }.map { attachment in
            let pageTitle = attachment.displayPageTitle
            let previewURL: URL?
            if let relativePath = attachment.relativePath {
                previewURL = try? attachmentStore.resolve(relativePath: relativePath)
            } else {
                previewURL = attachment.url
            }
            let faviconURL = attachment.faviconRelativePath.flatMap { relativePath in
                try? attachmentStore.resolve(relativePath: relativePath)
            }
            return AppViewModel.LedgerAttachment(
                id: attachment.id,
                kind: uiAttachmentKind(attachment.kind),
                name: pageTitle ?? attachment.originalFilename,
                subtitle: attachment.kind == .url
                    ? pageTitle.map { _ in attachment.originalFilename }
                    : attachment.contentType?.localizedDescription,
                previewURL: previewURL,
                faviconURL: faviconURL
            )
        }
        return AppViewModel.LedgerItem(
            id: item.id,
            kind: item.kind == .task ? .task : .note,
            title: item.displayTitle,
            detail: detail,
            text: item.text,
            searchableText: CaptureTagParser.removingTagMentions(
                in: item.text,
                matching: item.tags.map(\.name)
            ),
            createdAt: item.createdAt,
            dueDate: item.dueDate,
            folderID: item.list?.id,
            folderName: item.list?.name,
            sourceApp: item.sourceApplicationName,
            isPinned: item.isPinned,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            isArchived: item.isArchived,
            isTrashed: item.isTrashed,
            sortOrder: item.sortOrder,
            tags: item.tags
                .map {
                    AppViewModel.TagSummary(
                        id: $0.id,
                        name: $0.name,
                        colorSeed: $0.colorSeed ?? TagColorSeed.stable(for: $0.id)
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            attachments: attachments
        )
    }

    private func uiAttachmentKind(_ kind: AttachmentKind) -> AppViewModel.LedgerAttachment.Kind {
        switch kind {
        case .file: .file
        case .image: .image
        case .url: .link
        case .screenshot: .screenshot
        }
    }

    func show(_ error: Error) {
        viewModel.openExpanded()
        viewModel.errorMessage = error.localizedDescription
    }
}
