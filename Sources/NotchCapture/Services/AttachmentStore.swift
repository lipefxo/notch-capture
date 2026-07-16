import Foundation
import UniformTypeIdentifiers

struct StoredAttachment: Sendable, Equatable {
    let id: UUID
    let relativePath: String
    let originalFilename: String
    let typeIdentifier: String
    let kind: AttachmentKind
}

struct AttachmentStore: @unchecked Sendable {
    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = support
                .appendingPathComponent("NotchCapture", isDirectory: true)
                .appendingPathComponent("Attachments", isDirectory: true)
                .standardizedFileURL
        }
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func storeFile(
        at sourceURL: URL,
        id: UUID = UUID(),
        kind: AttachmentKind? = nil
    ) throws -> StoredAttachment {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let filename = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let type = UTType(filenameExtension: sourceURL.pathExtension) ?? .data
        let relativePath = uniqueRelativePath(id: id, filename: filename)
        let destination = try resolve(relativePath: relativePath)
        let temporary = rootURL.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
        do {
            try fileManager.copyItem(at: sourceURL, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw AttachmentStoreError.copyFailed(error)
        }
        return StoredAttachment(
            id: id,
            relativePath: relativePath,
            originalFilename: filename,
            typeIdentifier: type.identifier,
            kind: kind ?? (type.conforms(to: .image) ? .image : .file)
        )
    }

    func storeData(
        _ data: Data,
        filename: String,
        type: UTType,
        id: UUID = UUID(),
        kind: AttachmentKind
    ) throws -> StoredAttachment {
        guard !data.isEmpty else { throw AttachmentStoreError.emptyData }
        let relativePath = uniqueRelativePath(id: id, filename: filename)
        let destination = try resolve(relativePath: relativePath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AttachmentStoreError.destinationExists
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw AttachmentStoreError.copyFailed(error)
        }
        return StoredAttachment(
            id: id,
            relativePath: relativePath,
            originalFilename: filename,
            typeIdentifier: type.identifier,
            kind: kind
        )
    }

    func resolve(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty else { throw AttachmentStoreError.invalidRelativePath }
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard resolved.path.hasPrefix(rootPath), resolved.path != rootURL.path else {
            throw AttachmentStoreError.invalidRelativePath
        }
        return resolved
    }

    func remove(relativePath: String) throws {
        let url = try resolve(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func uniqueRelativePath(id: UUID, filename: String) -> String {
        let safeName = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(id.uuidString)-\(safeName)"
    }
}

enum AttachmentStoreError: LocalizedError {
    case invalidRelativePath
    case emptyData
    case destinationExists
    case copyFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath: "The attachment path is outside the attachment store."
        case .emptyData: "An empty attachment cannot be stored."
        case .destinationExists: "An attachment with this identifier and filename already exists."
        case let .copyFailed(error): "The attachment could not be stored: \(error.localizedDescription)"
        }
    }
}
