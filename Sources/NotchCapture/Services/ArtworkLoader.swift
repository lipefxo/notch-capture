import AppKit
import Foundation

@MainActor
final class ArtworkLoader {
    private let runner: any AppleScriptRunning
    private let cache = NSCache<NSString, NSImage>()

    init(
        runner: any AppleScriptRunning,
        capacity: Int = 20,
        totalCostLimit: Int = 8 * 1_024 * 1_024
    ) {
        self.runner = runner
        cache.countLimit = max(1, capacity)
        cache.totalCostLimit = max(1, totalCostLimit)
    }

    func artwork(for snapshot: NowPlayingSnapshot) async -> NSImage? {
        if let cached = cache.object(forKey: snapshot.trackKey as NSString) {
            return cached
        }

        let image: NSImage?
        switch snapshot.source {
        case .spotify:
            image = await fetchSpotifyArtwork(snapshot.artworkURL)
        case .appleMusic:
            image = await fetchMusicArtwork()
        }
        guard let image else { return nil }
        let prepared = image.scaledToFit(maxDimension: 160)
        insert(prepared, for: snapshot.trackKey)
        return prepared
    }

    private func fetchSpotifyArtwork(_ url: URL?) async -> NSImage? {
        guard let url, url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        } catch is CancellationError {
            // Propagate cancellation to the caller via Task.isCancelled so a
            // cancelled first-launch refresh can retry instead of caching failure.
            return nil
        } catch {
            return nil
        }
    }

    private func fetchMusicArtwork() async -> NSImage? {
        let source = """
        tell application \"Music\"
            if player state is stopped then return missing value
            try
                return raw data of artwork 1 of current track
            on error
                return data of artwork 1 of current track
            end try
        end tell
        """
        guard case let .data(data) = try? await runner.run(source) else { return nil }
        return NSImage(data: data)
    }

    private func insert(_ image: NSImage, for key: String) {
        let pixelCost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: key as NSString, cost: pixelCost)
    }
}

private extension NSImage {
    func scaledToFit(maxDimension: CGFloat) -> NSImage {
        guard size.width > maxDimension || size.height > maxDimension else { return self }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: target)
        result.lockFocus()
        draw(in: CGRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}
