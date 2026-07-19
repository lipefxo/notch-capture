import AppKit
import Foundation
import UniformTypeIdentifiers

struct FaviconData: Sendable, Equatable {
    let data: Data
    let typeIdentifier: String
    let filename: String
}

protocol FaviconFetching: Sendable {
    func fetchFavicon(for pageURL: URL) async -> FaviconData?
}

/// A deliberately small, direct favicon resolver. It has no shared cache or
/// cookies: each captured URL gets one bounded, best-effort lookup.
struct FaviconFetcher: FaviconFetching {
    private static let maximumHTMLBytes = 512 * 1_024
    private static let maximumImageBytes = 1 * 1_024 * 1_024
    private static let maximumCandidates = 12

    private let session: URLSession

    init(session: URLSession = FaviconFetcher.makeEphemeralSession()) {
        self.session = session
    }

    func fetchFavicon(for pageURL: URL) async -> FaviconData? {
        guard Self.isHTTPURL(pageURL),
              let (htmlData, response) = await request(pageURL, maximumBytes: Self.maximumHTMLBytes),
              let resolvedPageURL = response.url else {
            return nil
        }
        let html = String(decoding: htmlData, as: UTF8.self)

        let candidates = Self.iconCandidates(in: html, baseURL: resolvedPageURL)
        for candidate in candidates.prefix(Self.maximumCandidates) {
            guard let (data, response) = await request(candidate.url, maximumBytes: Self.maximumImageBytes),
                  let image = Self.validatedImage(data: data, response: response, sourceURL: candidate.url) else {
                continue
            }
            return image
        }
        return nil
    }

    private func request(_ url: URL, maximumBytes: Int) async -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= maximumBytes,
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode) else {
                return nil
            }
            return (data, http)
        } catch {
            return nil
        }
    }

    private static func validatedImage(
        data: Data,
        response: HTTPURLResponse,
        sourceURL: URL
    ) -> FaviconData? {
        guard !data.isEmpty,
              let image = NSImage(data: data),
              image.representations.contains(where: { $0 is NSBitmapImageRep }) else {
            return nil
        }

        let declaredType = response.mimeType.flatMap {
            UTType(tag: $0, tagClass: .mimeType, conformingTo: .image)
        }
            ?? UTType(filenameExtension: sourceURL.pathExtension)
        guard let type = declaredType, type.conforms(to: .image) else { return nil }
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let filenameExtension = type.preferredFilenameExtension
            ?? (sourceExtension.isEmpty ? "png" : sourceExtension)
        return FaviconData(
            data: data,
            typeIdentifier: type.identifier,
            filename: "Favicon.\(filenameExtension)"
        )
    }

    private struct Candidate {
        let url: URL
        let relationPriority: Int
        let sizeDistance: Int
        let sourceOrder: Int
    }

    private static func iconCandidates(in html: String, baseURL: URL) -> [Candidate] {
        var candidates: [Candidate] = []
        var seenURLs = Set<URL>()
        var sourceOrder = 0

        for attributes in linkAttributes(in: html) {
            defer { sourceOrder += 1 }
            guard let rel = attributes["rel"]?.lowercased(),
                  let href = attributes["href"],
                  let relationPriority = iconPriority(for: rel),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  isHTTPURL(url),
                  seenURLs.insert(url).inserted else {
                continue
            }
            candidates.append(
                Candidate(
                    url: url,
                    relationPriority: relationPriority,
                    sizeDistance: sizeDistance(from: attributes["sizes"]),
                    sourceOrder: sourceOrder
                )
            )
        }

        if let origin = originURL(for: baseURL) {
            let fallback = origin.appendingPathComponent("favicon.ico")
            if seenURLs.insert(fallback).inserted {
                candidates.append(
                    Candidate(
                        url: fallback,
                        relationPriority: 2,
                        sizeDistance: 0,
                        sourceOrder: sourceOrder
                    )
                )
            }
        }

        return candidates.sorted {
            if $0.relationPriority != $1.relationPriority {
                return $0.relationPriority < $1.relationPriority
            }
            if $0.sizeDistance != $1.sizeDistance {
                return $0.sizeDistance < $1.sizeDistance
            }
            return $0.sourceOrder < $1.sourceOrder
        }
    }

    private static func linkAttributes(in html: String) -> [[String: String]] {
        guard let linkExpression = try? NSRegularExpression(
            pattern: #"<link\b([^>]*)>"#,
            options: [.caseInsensitive]
        ), let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:\-.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        return linkExpression.matches(in: html, range: range).map { linkMatch in
            let attributesRange = linkMatch.range(at: 1)
            var attributes: [String: String] = [:]
            for match in attributeExpression.matches(in: html, range: attributesRange) {
                guard let nameRange = Range(match.range(at: 1), in: html) else { continue }
                let valueRange = [2, 3, 4].lazy.compactMap { index in
                    match.range(at: index).location == NSNotFound ? nil : Range(match.range(at: index), in: html)
                }.first
                guard let valueRange else { continue }
                attributes[String(html[nameRange]).lowercased()] = String(html[valueRange])
            }
            return attributes
        }
    }

    private static func iconPriority(for rel: String) -> Int? {
        let tokens = Set(rel.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() })
        if tokens.contains("apple-touch-icon") || tokens.contains("apple-touch-icon-precomposed") {
            return 1
        }
        return tokens.contains("icon") ? 0 : nil
    }

    private static func sizeDistance(from sizes: String?) -> Int {
        guard let sizes else { return 1_000 }
        let dimensions = sizes.lowercased().split(whereSeparator: { $0.isWhitespace }).compactMap { token -> Int? in
            let components = token.split(separator: "x", maxSplits: 1)
            guard components.count == 2,
                  let width = Int(components[0]),
                  let height = Int(components[1]) else {
                return nil
            }
            return max(width, height)
        }
        guard let closest = dimensions.map({ abs($0 - 32) }).min() else { return 999 }
        return closest
    }

    private static func originURL(for url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
