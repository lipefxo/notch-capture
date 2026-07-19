import AppKit
import Foundation
import QuickLookThumbnailing

struct ThumbnailRequest: Hashable, Sendable {
    let fileURL: URL
    let size: CGSize
    let scale: CGFloat

    fileprivate var cacheKey: String {
        let standardizedURL = fileURL.standardizedFileURL.absoluteString
        return "\(standardizedURL)|\(size.width)x\(size.height)@\(scale)"
    }
}

protocol ThumbnailGenerating: Sendable {
    func generateThumbnail(for request: ThumbnailRequest) async -> CGImage?
}

struct QuickLookThumbnailGeneratorAdapter: ThumbnailGenerating {
    func generateThumbnail(for request: ThumbnailRequest) async -> CGImage? {
        let quickLookRequest = QLThumbnailGenerator.Request(
            fileAt: request.fileURL,
            size: request.size,
            scale: request.scale,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: quickLookRequest)
            .cgImage
    }
}

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private struct InFlightRequest {
        let id: UUID
        let task: Task<CGImage?, Never>
    }

    private let generator: any ThumbnailGenerating
    private let cache = NSCache<NSString, CGImage>()
    private var inFlight: [String: InFlightRequest] = [:]

    init(
        generator: any ThumbnailGenerating = QuickLookThumbnailGeneratorAdapter(),
        countLimit: Int = 256,
        totalCostLimit: Int = 16 * 1_024 * 1_024
    ) {
        self.generator = generator
        cache.countLimit = max(1, countLimit)
        cache.totalCostLimit = max(1, totalCostLimit)
    }

    func thumbnail(for request: ThumbnailRequest) async -> CGImage? {
        let key = request.cacheKey
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.task.value
        }

        let id = UUID()
        let generator = generator
        let task = Task { await generator.generateThumbnail(for: request) }
        inFlight[key] = InFlightRequest(id: id, task: task)
        let image = await task.value

        // A purge or a future replacement must not let an older request write
        // stale pixels into the cache after its await resumes.
        guard inFlight[key]?.id == id else { return image }
        inFlight[key] = nil
        if let image {
            cache.setObject(
                image,
                forKey: key as NSString,
                cost: max(1, image.bytesPerRow * image.height)
            )
        }
        return image
    }

    func removeAllCachedThumbnails() {
        cache.removeAllObjects()
        inFlight.removeAll()
    }
}
