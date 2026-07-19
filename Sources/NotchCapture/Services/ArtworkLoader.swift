import AppKit
import Foundation

@MainActor
final class ArtworkLoader {
    private let runner: AppleScriptRunner
    private let capacity: Int
    private var cache: [String: NSImage] = [:]
    private var recency: [String] = []

    init(runner: AppleScriptRunner, capacity: Int = 20) {
        self.runner = runner
        self.capacity = max(1, capacity)
    }

    func artwork(for snapshot: NowPlayingSnapshot) async -> NSImage? {
        if let cached = cache[snapshot.trackKey] {
            touch(snapshot.trackKey)
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
        let prepared = image.scaledToFit(maxDimension: 600)
        insert(prepared, for: snapshot.trackKey)
        return prepared
    }

    private func fetchSpotifyArtwork(_ url: URL?) async -> NSImage? {
        guard let url, url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
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
        cache[key] = image
        touch(key)
        while recency.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
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
