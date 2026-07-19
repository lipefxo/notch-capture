import CoreGraphics
import XCTest
@testable import NotchCapture

private actor TestThumbnailGenerator: ThumbnailGenerating {
    private var responses: [CGImage?]
    private var generationCount = 0

    init(responses: [CGImage?]) {
        self.responses = responses
    }

    func generateThumbnail(for _: ThumbnailRequest) async -> CGImage? {
        generationCount += 1
        return responses.isEmpty ? nil : responses.removeFirst()
    }

    func count() -> Int { generationCount }
}

private actor BlockingThumbnailGenerator: ThumbnailGenerating {
    private let image: CGImage
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var generationCount = 0

    init(image: CGImage) {
        self.image = image
    }

    func generateThumbnail(for _: ThumbnailRequest) async -> CGImage? {
        generationCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return image
    }

    func count() -> Int { generationCount }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

final class ThumbnailLoaderTests: XCTestCase {
    func testCachesByURLAndPixelDimensions() async throws {
        let image = try makeImage()
        let generator = TestThumbnailGenerator(responses: [image, image])
        let loader = ThumbnailLoader(generator: generator)
        let first = request(width: 112, height: 104)

        let firstResult = await loader.thumbnail(for: first)
        let cachedResult = await loader.thumbnail(for: first)
        let countAfterCacheHit = await generator.count()
        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(cachedResult)
        XCTAssertEqual(countAfterCacheHit, 1)

        let distinctSizeResult = await loader.thumbnail(for: request(width: 224, height: 208))
        let countAfterDistinctSize = await generator.count()
        XCTAssertNotNil(distinctSizeResult)
        XCTAssertEqual(countAfterDistinctSize, 2)
    }

    func testFailedGenerationCanRetry() async throws {
        let image = try makeImage()
        let generator = TestThumbnailGenerator(responses: [nil, image])
        let loader = ThumbnailLoader(generator: generator)
        let request = request(width: 112, height: 104)

        let failedResult = await loader.thumbnail(for: request)
        let retriedResult = await loader.thumbnail(for: request)
        let retryCount = await generator.count()
        XCTAssertNil(failedResult)
        XCTAssertNotNil(retriedResult)
        XCTAssertEqual(retryCount, 2)
    }

    func testConcurrentRequestsCoalesceAndPurgedResultsStayUncached() async throws {
        let image = try makeImage()
        let generator = BlockingThumbnailGenerator(image: image)
        let loader = ThumbnailLoader(generator: generator)
        let request = request(width: 112, height: 104)

        async let first = loader.thumbnail(for: request)
        async let second = loader.thumbnail(for: request)
        await waitUntil { await generator.count() == 1 }
        await loader.removeAllCachedThumbnails()
        await generator.releaseNext()
        let firstResult = await first
        let secondResult = await second
        let coalescedCount = await generator.count()
        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(secondResult)
        XCTAssertEqual(coalescedCount, 1)

        async let afterPurge = loader.thumbnail(for: request)
        await waitUntil { await generator.count() == 2 }
        await generator.releaseNext()
        let afterPurgeResult = await afterPurge
        XCTAssertNotNil(afterPurgeResult)
    }

    private func request(width: CGFloat, height: CGFloat) -> ThumbnailRequest {
        ThumbnailRequest(
            fileURL: URL(fileURLWithPath: "/tmp/thumbnail-test.png"),
            size: CGSize(width: width, height: height),
            scale: 2
        )
    }

    private func makeImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }

    private func waitUntil(
        attempts: Int = 100,
        _ predicate: () async -> Bool
    ) async {
        for _ in 0..<attempts {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied")
    }
}
