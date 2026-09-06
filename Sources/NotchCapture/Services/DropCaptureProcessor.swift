import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The materialized values that a drop provider can contribute to one capture.
/// Keeping this separate from NSItemProvider makes the provider accounting
/// deterministic and keeps failed providers out of the item being persisted.
enum DropCapturePayload: Equatable, Sendable {
    case file(URL)
    case url(URL)
    case image(data: Data, typeIdentifier: String, filename: String)
    case text(String)
}

struct DropCaptureFailure: Error, Equatable, Sendable {
    enum Kind: String, Sendable {
        case unsupported
        case unreadable
    }

    let kind: Kind
    let providerIndex: Int
    let label: String?

    init(kind: Kind, providerIndex: Int, label: String? = nil) {
        self.kind = kind
        self.providerIndex = providerIndex
        self.label = label
    }
}

struct DropCaptureBatch: Equatable, Sendable {
    let attemptedCount: Int
    let payloads: [DropCapturePayload]
    let failures: [DropCaptureFailure]

    var succeededCount: Int { payloads.count }
    var failedCount: Int { failures.count }
    var allFailed: Bool { attemptedCount > 0 && payloads.isEmpty }

    /// The message is intentionally phrased as a manual retry instruction.
    /// A caller must never feed the original provider array back into a retry,
    /// since that would duplicate the providers that already succeeded.
    var feedbackMessage: String? {
        guard failedCount > 0 else { return nil }

        let labels = failures.compactMap { failure -> String? in
            let label = failure.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return label.isEmpty ? nil : label
        }
        let retryInstruction: String
        if labels.count == 1 {
            retryInstruction = "Try dragging “\(labels[0])” again."
        } else if !labels.isEmpty {
            let visibleLabels = labels.prefix(3).joined(separator: "”, “")
            let suffix = labels.count > 3 ? " and the other failed items" : ""
            retryInstruction = "Try dragging “\(visibleLabels)”\(suffix) again."
        } else {
            retryInstruction = attemptedCount == 1
                ? "Try dragging it again."
                : "Try dragging the failed items again."
        }

        if allFailed {
            let noun = attemptedCount == 1 ? "item" : "items"
            return "Nothing was captured. The dropped \(noun) couldn’t be read. \(retryInstruction)"
        }

        let succeeded = succeededCount == 1 ? "1 item" : "\(succeededCount) items"
        let failed = failedCount == 1 ? "1 item" : "\(failedCount) items"
        return "Captured \(succeeded). \(failed) couldn’t be read. \(retryInstruction)"
    }
}

/// Runs one load attempt for each provider and records the result without
/// retrying. The generic provider parameter is deliberate: tests can use
/// deterministic fixtures without constructing asynchronous AppKit providers.
@MainActor
enum DropCaptureProcessor {
    static func process<Provider>(
        _ providers: [Provider],
        load: @MainActor (Provider, Int) async -> Result<DropCapturePayload, DropCaptureFailure>
    ) async -> DropCaptureBatch {
        var payloads: [DropCapturePayload] = []
        var failures: [DropCaptureFailure] = []

        for (index, provider) in providers.enumerated() {
            switch await load(provider, index) {
            case let .success(payload):
                payloads.append(payload)
            case let .failure(failure):
                failures.append(failure)
            }
        }

        return DropCaptureBatch(
            attemptedCount: providers.count,
            payloads: payloads,
            failures: failures
        )
    }
}

enum DropCaptureImageRepresentation {
    private static let preferredTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif]

    /// Picks a concrete image representation using the same preference order
    /// as paste. A generic public.image provider is converted to PNG only when
    /// there is no concrete representation to preserve.
    static func preferredType(from identifiers: [String]) -> UTType {
        let registeredTypes = identifiers.compactMap(UTType.init)
        if let preferred = preferredTypes.first(where: { registeredTypes.contains($0) }) {
            return preferred
        }
        return registeredTypes.first(where: {
            $0 != .image && $0.conforms(to: .image)
        }) ?? .image
    }

    struct Materialized: Equatable, Sendable {
        let data: Data
        let typeIdentifier: String
        let filename: String
    }

    static func materialize(
        data: Data,
        declaredType: UTType,
        suggestedName: String?,
        index: Int
    ) -> Materialized? {
        guard !data.isEmpty else { return nil }

        if declaredType == .image {
            // The provider exposed only public.image, so retaining its bytes
            // with a guessed extension would mislabel the attachment. Decode
            // and normalize this one ambiguous case to a real PNG.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return Materialized(
                data: output as Data,
                typeIdentifier: UTType.png.identifier,
                filename: filename(suggestedName: nil, type: .png, index: index)
            )
        }

        return Materialized(
            data: data,
            typeIdentifier: declaredType.identifier,
            filename: filename(suggestedName: suggestedName, type: declaredType, index: index)
        )
    }

    static func filename(suggestedName: String?, type: UTType, index: Int) -> String {
        let trimmedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Dropped Image \(index)"
        guard let filenameExtension = type.preferredFilenameExtension else {
            return baseName
        }
        let currentExtension = URL(fileURLWithPath: baseName).pathExtension
        if !currentExtension.isEmpty,
           let currentType = UTType(filenameExtension: currentExtension),
           currentType.conforms(to: .image),
           currentType != type {
            let stem = String(baseName.dropLast(currentExtension.count + 1))
            return "\(stem).\(filenameExtension)"
        }
        guard currentExtension.isEmpty else {
            return baseName
        }
        return "\(baseName).\(filenameExtension)"
    }
}
