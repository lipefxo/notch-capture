import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension AppCoordinator {
    func captureManualText(_ text: String, folderID: UUID?) {
        do {
            let parsed = CaptureTagParser.parse(text)
            if parsed.isTagOnly, let name = parsed.tagNames.first {
                _ = try repository.createTag(name: name)
                reloadFromStore()
                return
            }
            let list = try folderID.map(findList)
            let payload: CapturePayload = if let url = CaptureURLParser.url(from: parsed.text) {
                .url(url)
            } else {
                .text(text)
            }
            let item = try repository.createItem(
                from: payload,
                origin: .manual,
                list: list,
                tagNames: parsed.tagNames
            )
            presentCaptureFeedback(for: item, feedback: .stayExpanded)
        } catch {
            show(error)
        }
    }

    func captureQuickSnippet(_ text: String, categoryID: UUID?) -> String? {
        do {
            let parsed = CaptureTagParser.parse(text)
            let payload: CapturePayload = if let url = CaptureURLParser.url(from: parsed.text) {
                .url(url)
            } else {
                .text(text)
            }
            let item = try repository.createItem(
                from: payload,
                origin: .manual,
                tagNames: parsed.tagNames
            )
            let category = try categoryID.map(findSnippetCategoryForCapture)
            try repository.setQuickSnippet(true, for: item, category: category)
            presentCaptureFeedback(for: item, feedback: .stayExpanded)
            return nil
        } catch {
            reloadFromStore()
            return error.localizedDescription
        }
    }

    private func findSnippetCategoryForCapture(_ id: UUID) throws -> SnippetCategory {
        let categories = try modelContainer.mainContext.fetch(FetchDescriptor<SnippetCategory>())
        guard let category = categories.first(where: { $0.id == id }) else {
            throw ItemRepositoryError.snippetCategoryNotFound(id)
        }
        return category
    }

    func captureComposerImages(
        text: String,
        images: [AppViewModel.ComposerImage],
        folderID: UUID?
    ) -> String? {
        do {
            let parsed = CaptureTagParser.parse(text)
            let list = try folderID.map(findList)
            let item = try repository.createItem(
                text: text,
                origin: .manual,
                list: list,
                tagNames: parsed.tagNames,
                imageAttachments: images.map {
                    ImageAttachmentPayload(
                        data: $0.data,
                        typeIdentifier: $0.typeIdentifier,
                        filename: $0.filename
                    )
                }
            )
            presentCaptureFeedback(for: item, feedback: .stayExpanded)
            return nil
        } catch {
            reloadFromStore()
            return error.localizedDescription
        }
    }

    func handleComposerImagePaste(from pasteboard: NSPasteboard) -> Bool {
        guard viewModel.surfaceState == .expanded,
              viewModel.keyboardFocus == .composer else {
            return false
        }
        let images = Self.composerImages(from: pasteboard)
        guard !images.isEmpty else { return false }
        viewModel.appendComposerImages(images)
        return true
    }

    static func composerImages(from pasteboard: NSPasteboard) -> [AppViewModel.ComposerImage] {
        (pasteboard.pasteboardItems ?? []).enumerated().compactMap { offset, item in
            let fileURL = item.string(forType: .fileURL).flatMap(URL.init(string:))
            let registeredTypes = item.types.compactMap { UTType($0.rawValue) }
            let preferredTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif]
            let imageType = preferredTypes.first(where: { registeredTypes.contains($0) })
                ?? registeredTypes.first(where: { $0 != .image && $0.conforms(to: .image) })

            if let imageType,
               let data = item.data(forType: NSPasteboard.PasteboardType(imageType.identifier)),
               !data.isEmpty {
                let filename = fileURL?.lastPathComponent.isEmpty == false
                    ? fileURL?.lastPathComponent
                    : nil
                return AppViewModel.ComposerImage(
                    data: data,
                    typeIdentifier: imageType.identifier,
                    filename: filename ?? pastedImageFilename(
                        suggestedName: nil,
                        type: imageType,
                        index: offset + 1
                    )
                )
            }

            if let fileURL {
                return loadPastedImageFile(at: fileURL, index: offset + 1)
            }
            return nil
        }
    }

    @discardableResult
    private func createCapture(
        payload: CapturePayload,
        origin: CaptureOrigin,
        source: CaptureSource = CaptureSource()
    ) throws -> CaptureItem {
        try repository.createItem(from: payload, origin: origin, source: source)
    }

    private func fileAttachment(_ url: URL, order: Int) throws -> Attachment {
        let stored = try attachmentStore.storeFile(at: url)
        return Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath,
            order: order
        )
    }

    private func dataAttachment(
        _ data: Data,
        filename: String,
        type: UTType,
        kind: AttachmentKind,
        order: Int
    ) throws -> Attachment {
        let stored = try attachmentStore.storeData(data, filename: filename, type: type, kind: kind)
        return Attachment(
            id: stored.id,
            kind: stored.kind,
            typeIdentifier: stored.typeIdentifier,
            originalFilename: stored.originalFilename,
            relativePath: stored.relativePath,
            order: order
        )
    }

    private func linkAttachment(_ url: URL, order: Int) -> Attachment {
        Attachment(
            kind: .url,
            typeIdentifier: UTType.url.identifier,
            originalFilename: url.host(percentEncoded: false) ?? url.absoluteString,
            url: url,
            order: order
        )
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var urls: [URL] = []
            var textParts: [String] = []
            var imagePayloads: [(Data, UTType)] = []
            var storedPaths: [String] = []

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await loadURL(from: provider, type: .fileURL) {
                    urls.append(url)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await loadURL(from: provider, type: .url) {
                    urls.append(url)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                          let data = await loadData(from: provider, type: .image) {
                    imagePayloads.append((data, .png))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await loadText(from: provider) {
                    textParts.append(text)
                }
            }

            do {
                var attachments = try urls.enumerated().map { index, url in
                    url.isFileURL ? try fileAttachment(url, order: index) : linkAttachment(url, order: index)
                }
                for (offset, payload) in imagePayloads.enumerated() {
                    attachments.append(try dataAttachment(
                        payload.0,
                        filename: "Dropped Image \(offset + 1).png",
                        type: payload.1,
                        kind: .image,
                        order: attachments.count
                    ))
                }
                storedPaths = attachments.compactMap(\.relativePath)
                let text = textParts.joined(separator: "\n")
                let item: CaptureItem
                if attachments.isEmpty, let url = CaptureURLParser.url(from: text) {
                    item = try repository.createItem(from: .url(url), origin: .drop)
                } else {
                    item = try repository.createItem(text: text, origin: .drop, attachments: attachments)
                }
                presentConfirmation(for: item)
            } catch {
                storedPaths.forEach { try? attachmentStore.remove(relativePath: $0) }
                show(error)
            }
        }
    }

    func loadPastedImages(from providers: [NSItemProvider], forComposerDraft draftID: UUID) {
        let previousTask = composerPasteTask
        composerPasteTask = Task { @MainActor [weak self] in
            _ = await previousTask?.value
            guard let self else { return }
            guard !Task.isCancelled else { return }
            var images: [AppViewModel.ComposerImage] = []

            for (offset, provider) in providers.enumerated() {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let type = preferredImageType(for: provider)
                    guard let data = await loadData(from: provider, type: type), !data.isEmpty else {
                        continue
                    }
                    images.append(
                        AppViewModel.ComposerImage(
                            data: data,
                            typeIdentifier: type.identifier,
                            filename: Self.pastedImageFilename(
                                suggestedName: provider.suggestedName,
                                type: type,
                                index: offset + 1
                            )
                        )
                    )
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                          let url = await loadURL(from: provider, type: .fileURL),
                          let image = Self.loadPastedImageFile(at: url, index: offset + 1) {
                    images.append(image)
                }
            }

            guard !Task.isCancelled else { return }
            if images.isEmpty {
                viewModel.showComposerPasteError(
                    "The pasted image couldn’t be read.",
                    forComposerDraft: draftID
                )
            } else {
                viewModel.appendComposerImages(images, toComposerDraft: draftID)
            }
        }
    }

    static func loadPastedImageFile(at url: URL, index: Int) -> AppViewModel.ComposerImage? {
        guard url.isFileURL else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let type = resourceType ?? UTType(filenameExtension: url.pathExtension)
        guard let type, type.conforms(to: .image),
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        let filename = url.lastPathComponent.isEmpty
            ? pastedImageFilename(suggestedName: nil, type: type, index: index)
            : url.lastPathComponent
        return AppViewModel.ComposerImage(
            data: data,
            typeIdentifier: type.identifier,
            filename: filename
        )
    }

    private func preferredImageType(for provider: NSItemProvider) -> UTType {
        let registeredTypes = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        let preferredTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif]
        if let preferred = preferredTypes.first(where: { registeredTypes.contains($0) }) {
            return preferred
        }
        return registeredTypes.first(where: { $0 != .image && $0.conforms(to: .image) }) ?? .image
    }

    private static func pastedImageFilename(
        suggestedName: String?,
        type: UTType,
        index: Int
    ) -> String {
        let trimmedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Pasted Image \(index)"
        guard URL(fileURLWithPath: baseName).pathExtension.isEmpty,
              let filenameExtension = type.preferredFilenameExtension else {
            return baseName
        }
        return "\(baseName).\(filenameExtension)"
    }

    private func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

}
