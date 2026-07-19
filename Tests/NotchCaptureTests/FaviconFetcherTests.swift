import Foundation
import XCTest
@testable import NotchCapture

final class FaviconURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.requestedURLs.append(url)
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FaviconFetcherTests: XCTestCase {
    private let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8xQAAAABJRU5ErkJggg==")!

    override func tearDown() {
        FaviconURLProtocol.handler = nil
        FaviconURLProtocol.requestedURLs = []
        super.tearDown()
    }

    func testResolvesRelativeShortcutIconAndPrefersTheClosestStandardSize() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/articles/one"))
        FaviconURLProtocol.handler = { [pngData] request in
            let url = request.url!
            if url.path == "/articles/one" {
                let html = """
                <link rel="apple-touch-icon" href="/apple.png" sizes="180x180">
                <link href="/tiny.png" rel="icon" sizes="16x16">
                <link rel="shortcut icon" href="icons/site.png" sizes="32x32">
                """
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), pngData)
        }

        let favicon = await FaviconFetcher(session: Self.session()).fetchFavicon(for: pageURL)

        XCTAssertEqual(favicon?.data, pngData)
        XCTAssertEqual(favicon?.typeIdentifier, "public.png")
        XCTAssertEqual(
            FaviconURLProtocol.requestedURLs.map(\.path),
            ["/articles/one", "/articles/icons/site.png"]
        )
    }

    func testFallsBackToOriginFaviconAndSilentlyRejectsUndecodableData() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        FaviconURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/path" {
                return (Self.response(url, mimeType: "text/html"), Data("<html></html>".utf8))
            }
            return (Self.response(url, mimeType: "image/png"), Data("not an image".utf8))
        }

        let favicon = await FaviconFetcher(session: Self.session()).fetchFavicon(for: pageURL)

        XCTAssertNil(favicon)
        XCTAssertEqual(FaviconURLProtocol.requestedURLs.map(\.path), ["/path", "/favicon.ico"])
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ url: URL, mimeType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType]
        )!
    }
}
