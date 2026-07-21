import AppKit
import Foundation
import UniformTypeIdentifiers

struct FaviconData: Sendable, Equatable {
    let data: Data
    let typeIdentifier: String
    let filename: String
}

struct LinkMetadata: Sendable, Equatable {
    let title: String?
    let favicon: FaviconData?
}

protocol LinkMetadataFetching: Sendable {
    func fetchMetadata(for pageURL: URL) async -> LinkMetadata?
}

/// A deliberately small, direct page metadata resolver. It has no shared cache
/// or cookies: each newly captured URL gets one bounded, best-effort lookup.
struct LinkMetadataFetcher: LinkMetadataFetching {
    // YouTube watch pages currently place Open Graph/title metadata after the
    // first 600 KB of HTML, so keep a bounded allowance large enough for them.
    private static let maximumHTMLBytes = 2 * 1_024 * 1_024
    private static let maximumImageBytes = 1 * 1_024 * 1_024
    private static let maximumCandidates = 12
    private static let maximumTitleCharacters = 512
    private static let commonHTMLEntities = [
        "nbsp": " ",
        "ndash": "–",
        "mdash": "—",
        "hellip": "…",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "copy": "©",
        "reg": "®",
        "trade": "™",
    ]

    private let session: URLSession

    init(session: URLSession = LinkMetadataFetcher.makeEphemeralSession()) {
        self.session = session
    }

    func fetchMetadata(for pageURL: URL) async -> LinkMetadata? {
        guard Self.isHTTPURL(pageURL),
              let (htmlData, response) = await request(
                pageURL,
                maximumBytes: Self.maximumHTMLBytes,
                accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
              ),
              let resolvedPageURL = response.url else {
            return nil
        }
        let html = String(decoding: htmlData, as: UTF8.self)
        let title = Self.pageTitle(in: html)

        let candidates = Self.iconCandidates(in: html, baseURL: resolvedPageURL)
        for candidate in candidates.prefix(Self.maximumCandidates) {
            guard let (data, response) = await request(
                candidate.url,
                maximumBytes: Self.maximumImageBytes,
                accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
            ),
                  let image = Self.validatedImage(data: data, response: response, sourceURL: candidate.url) else {
                continue
            }
            return LinkMetadata(title: title, favicon: image)
        }
        return LinkMetadata(title: title, favicon: nil)
    }

    private func request(
        _ url: URL,
        maximumBytes: Int,
        accept: String
    ) async -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
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

    private static func pageTitle(in html: String) -> String? {
        let meta = elementAttributes(named: "meta", in: html)
        for key in ["og:title", "twitter:title"] {
            for attributes in meta {
                let identifiers = [attributes["property"], attributes["name"]]
                    .compactMap { $0?.lowercased() }
                guard identifiers.contains(key),
                      let content = attributes["content"],
                      let title = normalizedTitle(content) else {
                    continue
                }
                return title
            }
        }

        guard let expression = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return normalizedTitle(String(html[titleRange]))
    }

    private static func normalizedTitle(_ rawTitle: String) -> String? {
        let withoutMarkup = rawTitle.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let withCommonEntitiesDecoded = commonHTMLEntities.reduce(withoutMarkup) { partial, entity in
            partial.replacingOccurrences(
                of: "&\(entity.key);",
                with: entity.value,
                options: .caseInsensitive
            )
        }
        let decoded = CFXMLCreateStringByUnescapingEntities(
            nil,
            withCommonEntitiesDecoded as CFString,
            nil
        ) as String? ?? withCommonEntitiesDecoded
        let normalized = decoded
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumTitleCharacters))
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

        for attributes in elementAttributes(named: "link", in: html) {
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

    private static func elementAttributes(named elementName: String, in html: String) -> [[String: String]] {
        guard let elementExpression = try? NSRegularExpression(
            pattern: #"<"# + NSRegularExpression.escapedPattern(for: elementName) + #"\b([^>]*)>"#,
            options: [.caseInsensitive]
        ), let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:\-.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        return elementExpression.matches(in: html, range: range).map { elementMatch in
            let attributesRange = elementMatch.range(at: 1)
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
