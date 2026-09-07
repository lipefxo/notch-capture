import Foundation

protocol ModelUsageFetching: Sendable {
    func fetchSnapshot(
        for provider: ModelUsageProvider,
        credential: ModelUsageCredential,
        now: Date
    ) async throws -> ModelUsageSnapshot
}

enum ModelUsageFetchError: Equatable, LocalizedError, Sendable {
    case notSignedIn
    case unauthorized
    case unavailable
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Not signed in"
        case .unauthorized:
            "Sign in again to refresh usage"
        case .unavailable:
            "Couldn't reach usage"
        case .unreadable:
            "Usage response wasn't readable"
        }
    }

    func statusText(for provider: ModelUsageProvider) -> String {
        switch self {
        case .notSignedIn:
            provider.signInHint
        case .unauthorized:
            switch provider {
            case .openAI: "Sign in with Codex again"
            case .cursor: "Sign in to Cursor again"
            }
        case .unavailable:
            switch provider {
            case .openAI: "Couldn't reach ChatGPT usage"
            case .cursor: "Couldn't reach Cursor usage"
            }
        case .unreadable:
            "Usage response wasn't readable"
        }
    }
}

struct ModelUsageClient: ModelUsageFetching {
    var session: URLSession
    var openAIUsageURL: URL
    var cursorUsageURL: URL

    init(
        session: URLSession = ModelUsageClient.makeEphemeralSession(),
        openAIUsageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        cursorUsageURL: URL = URL(string: "https://cursor.com/api/usage-summary")!
    ) {
        self.session = session
        self.openAIUsageURL = openAIUsageURL
        self.cursorUsageURL = cursorUsageURL
    }

    func fetchSnapshot(
        for provider: ModelUsageProvider,
        credential: ModelUsageCredential,
        now: Date
    ) async throws -> ModelUsageSnapshot {
        switch provider {
        case .openAI:
            let data = try await perform(openAIRequest(credential: credential))
            do {
                return try ModelUsageSnapshotBuilder.openAI(from: data, now: now)
            } catch {
                throw ModelUsageFetchError.unreadable
            }
        case .cursor:
            let data = try await perform(cursorRequest(credential: credential))
            do {
                return try ModelUsageSnapshotBuilder.cursor(from: data, now: now)
            } catch {
                throw ModelUsageFetchError.unreadable
            }
        }
    }

    private func openAIRequest(credential: ModelUsageCredential) throws -> URLRequest {
        guard case let .bearer(token, accountID) = credential else {
            throw ModelUsageFetchError.unauthorized
        }
        var request = URLRequest(url: openAIUsageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    private func cursorRequest(credential: ModelUsageCredential) throws -> URLRequest {
        guard case let .sessionCookie(cookie) = credential else {
            throw ModelUsageFetchError.unauthorized
        }
        var request = URLRequest(url: cursorUsageURL)
        request.httpMethod = "GET"
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ModelUsageFetchError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ModelUsageFetchError.unavailable
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ModelUsageFetchError.unauthorized
        default:
            throw ModelUsageFetchError.unavailable
        }
    }

    static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}
