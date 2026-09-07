import Foundation
import XCTest
@testable import NotchCapture

final class ModelUsageTests: XCTestCase {
    func testOpenAISnapshotMapsSessionAndWeeklyWindows() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 6,
              "reset_at": 1700007200,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 24,
              "reset_at": 1700600000,
              "limit_window_seconds": 604800
            }
          },
          "credits": { "has_credits": true, "unlimited": false, "balance": "5.39" }
        }
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try ModelUsageSnapshotBuilder.openAI(from: json, now: now)

        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertEqual(snapshot.headline, "94% left this session")
        XCTAssertEqual(snapshot.remainingFraction ?? -1, 0.94, accuracy: 0.0001)
        XCTAssertEqual(snapshot.meters.map(\.id), ["session", "weekly", "credits"])
        XCTAssertEqual(snapshot.meters[0].remainingText, "94% left")
        XCTAssertEqual(snapshot.meters[0].resetsText, "Resets in 2h")
        XCTAssertEqual(snapshot.meters[1].title, "Weekly")
        XCTAssertEqual(snapshot.meters[2].remainingText, "$5.39 left")
    }

    func testCursorSnapshotMapsPlanCountsAndModelPools() throws {
        let json = """
        {
          "membershipType": "pro",
          "isUnlimited": false,
          "billingCycleEnd": "2026-09-14T00:00:00.000Z",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 1240,
              "limit": 2000,
              "remaining": 760,
              "autoPercentUsed": 58,
              "apiPercentUsed": 69,
              "totalPercentUsed": 62
            },
            "onDemand": { "enabled": true, "used": 2309 }
          }
        }
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try ModelUsageSnapshotBuilder.cursor(from: json, now: now)

        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.headline, "38% left")
        XCTAssertEqual(snapshot.remainingFraction ?? 0, 0.38, accuracy: 0.0001)
        XCTAssertEqual(snapshot.meters[0].usedText, "62% used")
        XCTAssertEqual(snapshot.meters[1].title, "Cursor Models")
        XCTAssertEqual(snapshot.meters[1].remainingText, "42% left")
        XCTAssertEqual(snapshot.meters[2].remainingText, "31% left")
        XCTAssertEqual(snapshot.meters[3].title, "On-demand")
    }

    func testCursorSnapshotPrefersAggregatePercentWhenBaseAllowanceIsExhausted() throws {
        let json = """
        {
          "membershipType": "pro",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 2000,
              "limit": 2000,
              "remaining": 0,
              "totalPercentUsed": 25.504909560723515
            }
          }
        }
        """.data(using: .utf8)!

        let snapshot = try ModelUsageSnapshotBuilder.cursor(from: json, now: Date())

        XCTAssertEqual(snapshot.headline, "74.5% left")
        XCTAssertEqual(snapshot.remainingFraction ?? 0, 0.7449509043927648, accuracy: 0.0001)
        XCTAssertEqual(snapshot.meters[0].usedText, "25.5% used")
    }

    func testCursorUnlimitedPlanHasFullRemainingFraction() throws {
        let json = """
        { "membershipType": "ultra", "isUnlimited": true }
        """.data(using: .utf8)!
        let snapshot = try ModelUsageSnapshotBuilder.cursor(from: json, now: Date())
        XCTAssertEqual(snapshot.headline, "Unlimited")
        XCTAssertEqual(snapshot.remainingFraction, 1.0)
    }

    func testWindowTitlesAndRemainingPercentFormatting() {
        XCTAssertEqual(ModelUsageFormatting.windowTitle(limitWindowSeconds: 18_000), "5h")
        XCTAssertEqual(ModelUsageFormatting.windowTitle(limitWindowSeconds: 604_800), "Weekly")
        XCTAssertEqual(ModelUsageFormatting.remainingPercentText(6), "94% left")
        XCTAssertEqual(ModelUsageFormatting.formattedPercent(12.5), "12.5")
        XCTAssertEqual(
            ModelUsageFormatting.resetsText(
                at: Date(timeIntervalSince1970: 1_700_003_600),
                now: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            "Resets in 1h"
        )
    }

    func testCursorCookieUsesWorkOSUserIDFromJWT() {
        let jwt = Self.jwt(sub: "google-oauth2|user_01ABC")
        XCTAssertEqual(JWTUserIdentifier.cursorUserID(from: jwt), "user_01ABC")
        XCTAssertEqual(
            ModelUsageSessionCookie.cursor(fromJWT: jwt),
            "user_01ABC%3A%3A\(jwt)"
        )
    }

    func testOpenAIAuthFileReadsNestedAccessToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("auth.json")
        try Data(#"""
        { "tokens": { "access_token": "tok_live", "account_id": "acct_123" } }
        """#.utf8).write(to: url)

        let file = try XCTUnwrap(ModelUsageAuthFile.openAI(from: url))
        XCTAssertEqual(file.accessToken, "tok_live")
        XCTAssertEqual(file.accountID, "acct_123")
    }

    func testCredentialStorePrefersCodexAndCursorAuthFiles() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".cursor"),
            withIntermediateDirectories: true
        )
        try Data(#"""
        { "tokens": { "access_token": "openai-token", "account_id": "acct" } }
        """#.utf8).write(to: home.appendingPathComponent(".codex/auth.json"))

        let jwt = Self.jwt(sub: "auth0|user_99")
        try Data("{\"accessToken\":\"\(jwt)\"}".utf8)
            .write(to: home.appendingPathComponent(".cursor/auth.json"))

        let store = ModelUsageCredentialStore(
            homeDirectory: home,
            environment: [:],
            keychain: StubKeychain()
        )

        let openAI = try XCTUnwrap(store.resolve(.openAI))
        XCTAssertEqual(openAI.credential, .bearer(token: "openai-token", accountID: "acct"))

        let cursor = try XCTUnwrap(store.resolve(.cursor))
        XCTAssertEqual(cursor.credential, .sessionCookie("user_99%3A%3A\(jwt)"))
    }

    func testCredentialStoreReadsCursorIDEStateDatabase() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseDirectory = home.appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage"
        )
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let jwt = Self.jwt(sub: "user_from_db")
        let databaseURL = databaseDirectory.appendingPathComponent("state.vscdb")
        try Self.writeCursorStateDatabase(at: databaseURL, accessToken: jwt)

        let store = ModelUsageCredentialStore(
            homeDirectory: home,
            environment: [:],
            keychain: StubKeychain()
        )
        let cursor = try XCTUnwrap(store.resolve(.cursor))
        XCTAssertEqual(cursor.credential, .sessionCookie("user_from_db%3A%3A\(jwt)"))
    }

    func testUsageClientSendsProviderAuthAndParsesBodies() async throws {
        let protocolClass = ModelUsageURLProtocol.self
        protocolClass.handler = { request in
            let url = request.url!
            if url.path.contains("wham/usage") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct")
                return (
                    Self.response(url, status: 200),
                    Data(#"""
                    { "plan_type": "pro", "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": 18000 } } }
                    """#.utf8)
                )
            }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Cookie"),
                "WorkosCursorSessionToken=user%3A%3Ajwt"
            )
            return (
                Self.response(url, status: 200),
                Data(#"""
                { "membershipType": "pro", "individualUsage": { "plan": { "used": 1, "limit": 10, "remaining": 9 } } }
                """#.utf8)
            )
        }
        defer {
            protocolClass.handler = nil
        }

        let client = ModelUsageClient(session: Self.session())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let openAI = try await client.fetchSnapshot(
            for: .openAI,
            credential: .bearer(token: "openai-token", accountID: "acct"),
            now: now
        )
        XCTAssertEqual(openAI.headline, "90% left this session")

        let cursor = try await client.fetchSnapshot(
            for: .cursor,
            credential: .sessionCookie("user%3A%3Ajwt"),
            now: now
        )
        XCTAssertEqual(cursor.headline, "9 left")
    }

    func testUsageClientMapsUnauthorizedResponses() async {
        ModelUsageURLProtocol.handler = { request in
            (Self.response(request.url!, status: 401), Data())
        }
        defer { ModelUsageURLProtocol.handler = nil }

        let client = ModelUsageClient(session: Self.session())
        do {
            _ = try await client.fetchSnapshot(
                for: .openAI,
                credential: .bearer(token: "expired", accountID: nil),
                now: .now
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? ModelUsageFetchError, .unauthorized)
        }
    }

    @MainActor
    func testServiceLoadsSignedInProvidersAndKeepsUnsignedOut() async {
        let fetcher = StubUsageFetcher(
            snapshots: [
                .openAI: ModelUsageViewState.preview.openAI.connection.snapshot!
            ]
        )
        let credentials = StubCredentials(
            resolutions: [
                .openAI: ModelUsageAuthResolution(
                    credential: .bearer(token: "tok", accountID: nil),
                    source: "test"
                )
            ]
        )
        let service = ModelUsageService(
            credentials: credentials,
            client: fetcher,
            refreshInterval: .seconds(60)
        )

        await service.refreshNow()

        XCTAssertEqual(service.state.openAI.connection.snapshot?.headline, "68% left this session")
        XCTAssertEqual(service.state.cursor.connection, .notSignedIn)
        XCTAssertEqual(service.state.compactSummary, "OpenAI 68%")
    }

    @MainActor
    func testViewModelForwardsModelUsageRefresh() {
        var refreshed = false
        var hooks = AppViewModel.Hooks()
        hooks.onRefreshModelUsage = { refreshed = true }
        let viewModel = AppViewModel(hooks: hooks)
        viewModel.refreshModelUsage()
        XCTAssertTrue(refreshed)
    }

    @MainActor
    func testCompactSummaryJoinsLoadedProviders() {
        var state = ModelUsageViewState.empty
        state.openAI.connection = .loaded(
            ModelUsageSnapshot(
                planName: "Plus",
                headline: "94% left this session",
                detail: "",
                remainingFraction: 0.94,
                meters: [],
                fetchedAt: .now
            )
        )
        state.cursor.connection = .loaded(
            ModelUsageSnapshot(
                planName: "Pro",
                headline: "38% left",
                detail: "",
                remainingFraction: 0.38,
                meters: [],
                fetchedAt: .now
            )
        )
        XCTAssertEqual(state.compactSummary, "OpenAI 94% · Cursor 38%")
        XCTAssertTrue(state.showsUtilityMeters)
        XCTAssertFalse(ModelUsageViewState.empty.showsUtilityMeters)
    }

    func testLogoFillTracksAndClampsRemainingAllowance() {
        var state = ModelUsageViewState.preview.openAI
        XCTAssertEqual(ModelUsageLogoFill.level(for: state), 0.68, accuracy: 0.0001)

        var snapshot = state.connection.snapshot!
        snapshot.remainingFraction = -0.25
        state.connection = .loaded(snapshot)
        XCTAssertEqual(ModelUsageLogoFill.level(for: state), 0, accuracy: 0.0001)

        snapshot.remainingFraction = 1.25
        state.connection = .loaded(snapshot)
        XCTAssertEqual(ModelUsageLogoFill.level(for: state), 1, accuracy: 0.0001)

        XCTAssertEqual(ModelUsageLogoFill.level(for: .empty), 0, accuracy: 0.0001)
        XCTAssertEqual(
            ModelUsageLogoFill.ghostOpacity(for: .empty),
            ModelUsageLogoFill.inactiveOpacity,
            accuracy: 0.0001
        )
    }

    func testLiquidWaveFillClosesAlongTheBottomEdgeInsteadOfDiagonally() {
        let paths = LiquidWaveGeometry.paths(
            in: CGRect(x: 0, y: 0, width: 20, height: 20),
            level: 0.5,
            phase: 0,
            amplitude: 0
        )

        XCTAssertTrue(paths.fill.contains(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(paths.fill.contains(CGPoint(x: 19, y: 1)))
        XCTAssertFalse(paths.fill.contains(CGPoint(x: 10, y: 19)))
    }

    private static func jwt(sub: String) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payload = Data("{\"sub\":\"\(sub)\"}".utf8).base64URLEncodedString()
        return "\(header).\(payload).sig"
    }

    private static func writeCursorStateDatabase(at url: URL, accessToken: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            url.path,
            """
            CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);
            INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', '\(accessToken)');
            """
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelUsageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private struct StubCredentials: ModelUsageCredentialReading {
    var resolutions: [ModelUsageProvider: ModelUsageAuthResolution]

    func resolve(_ provider: ModelUsageProvider) -> ModelUsageAuthResolution? {
        resolutions[provider]
    }
}

private struct StubUsageFetcher: ModelUsageFetching {
    var snapshots: [ModelUsageProvider: ModelUsageSnapshot]
    var errors: [ModelUsageProvider: ModelUsageFetchError] = [:]

    func fetchSnapshot(
        for provider: ModelUsageProvider,
        credential: ModelUsageCredential,
        now: Date
    ) async throws -> ModelUsageSnapshot {
        if let error = errors[provider] { throw error }
        guard let snapshot = snapshots[provider] else {
            throw ModelUsageFetchError.unavailable
        }
        return snapshot
    }
}

private struct StubKeychain: ModelUsageKeychainReading {
    var items: [String: String] = [:]

    func password(service: String, account: String?) -> String? {
        if let account {
            return items["\(service)|\(account)"]
        }
        return items[service]
    }
}

private final class ModelUsageURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
