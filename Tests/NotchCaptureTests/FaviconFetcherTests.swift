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

final class LinkMetadataFetcherTests: XCTestCase {
    private let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8xQAAAABJRU5ErkJggg==")!

    override func tearDown() {
        FaviconURLProtocol.handler = nil
        FaviconURLProtocol.requestedURLs = []
        super.tearDown()
    }

    func testPrefersOpenGraphTitleAndResolvesTheClosestRelativeIcon() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/articles/one"))
        FaviconURLProtocol.handler = { [pngData] request in
            let url = request.url!
            if url.path == "/articles/one" {
                let html = """
                <title>Fallback title</title>
                <meta content="Twitter title" name="twitter:title">
                <meta content="  Night &amp; Drive  " property="og:title">
                <link rel="apple-touch-icon" href="/apple.png" sizes="180x180">
                <link href="/tiny.png" rel="icon" sizes="16x16">
                <link rel="shortcut icon" href="icons/site.png" sizes="32x32">
                """
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), pngData)
        }

        let metadata = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)

        XCTAssertEqual(metadata?.title, "Night & Drive")
        XCTAssertEqual(metadata?.favicon?.data, pngData)
        XCTAssertEqual(metadata?.favicon?.typeIdentifier, "public.png")
        XCTAssertEqual(
            FaviconURLProtocol.requestedURLs.map(\.path),
            ["/articles/one", "/articles/icons/site.png"]
        )
    }

    func testFallsBackToNormalizedHTMLTitleWhenFaviconIsUndecodable() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        FaviconURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/path" {
                let html = "<title>  Tom &amp; Jerry <span>—</span>\n New&nbsp;Episode </title>"
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), Data("not an image".utf8))
        }

        let metadata = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)

        XCTAssertEqual(metadata?.title, "Tom & Jerry — New Episode")
        XCTAssertNil(metadata?.favicon)
        XCTAssertEqual(FaviconURLProtocol.requestedURLs.map(\.path), ["/path", "/favicon.ico"])
    }

    func testUsesTwitterTitleBeforeHTMLTitleAndLimitsStoredLength() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/watch"))
        let longTitle = String(repeating: "x", count: 600)
        FaviconURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/watch" {
                let html = "<title>Fallback</title><meta name='twitter:title' content='\(longTitle)'>"
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), Data())
        }

        let metadata = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)

        XCTAssertEqual(metadata?.title?.count, 512)
        XCTAssertTrue(metadata?.title?.allSatisfy { $0 == "x" } == true)
        XCTAssertNil(metadata?.favicon)
    }

    func testParsesMetadataFromAYouTubeSizedHTMLResponse() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let leadingPageData = String(repeating: " ", count: 700 * 1_024)
        FaviconURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/watch" {
                let html = "\(leadingPageData)<meta property='og:title' content='A YouTube Video'>"
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), Data())
        }

        let metadata = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)

        XCTAssertEqual(metadata?.title, "A YouTube Video")
        XCTAssertNil(metadata?.favicon)
    }

    func testReturnsFaviconWhenThePageHasNoUsableTitle() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/untitled"))
        FaviconURLProtocol.handler = { [pngData] request in
            let url = request.url!
            if url.path == "/untitled" {
                let html = "<meta property='og:title' content='   '><link rel='icon' href='/icon.png'>"
                return (Self.response(url, mimeType: "text/html"), Data(html.utf8))
            }
            return (Self.response(url, mimeType: "image/png"), pngData)
        }

        let metadata = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)

        XCTAssertNil(metadata?.title)
        XCTAssertEqual(metadata?.favicon?.data, pngData)
    }

    func testReturnsNilForUnsupportedOrFailedPageRequests() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/video")
        let unsupported = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: fileURL)
        XCTAssertNil(unsupported)
        XCTAssertTrue(FaviconURLProtocol.requestedURLs.isEmpty)

        let pageURL = try XCTUnwrap(URL(string: "https://example.com/missing"))
        FaviconURLProtocol.handler = nil
        let failed = await LinkMetadataFetcher(session: Self.session()).fetchMetadata(for: pageURL)
        XCTAssertNil(failed)
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
