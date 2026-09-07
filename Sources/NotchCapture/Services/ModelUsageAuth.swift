import Foundation
import Security
import SQLite3

enum ModelUsageCredential: Equatable, Sendable {
    case bearer(token: String, accountID: String?)
    case sessionCookie(String)
}

struct ModelUsageAuthResolution: Equatable, Sendable {
    var credential: ModelUsageCredential
    var source: String
}

protocol ModelUsageCredentialReading: Sendable {
    func resolve(_ provider: ModelUsageProvider) -> ModelUsageAuthResolution?
}

struct ModelUsageCredentialStore: ModelUsageCredentialReading {
    var homeDirectory: URL
    var environment: [String: String]
    var keychain: any ModelUsageKeychainReading

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychain: any ModelUsageKeychainReading = ModelUsageKeychainStore()
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.keychain = keychain
    }

    func resolve(_ provider: ModelUsageProvider) -> ModelUsageAuthResolution? {
        switch provider {
        case .openAI:
            return resolveOpenAI()
        case .cursor:
            return resolveCursor()
        }
    }

    private func resolveOpenAI() -> ModelUsageAuthResolution? {
        for url in openAIAuthFileURLs {
            if let file = ModelUsageAuthFile.openAI(from: url) {
                return ModelUsageAuthResolution(
                    credential: .bearer(token: file.accessToken, accountID: file.accountID),
                    source: url.path
                )
            }
        }
        if let token = keychain.password(service: "Codex Auth", account: nil) {
            return ModelUsageAuthResolution(
                credential: .bearer(token: token, accountID: nil),
                source: "keychain:Codex Auth"
            )
        }
        return nil
    }

    private func resolveCursor() -> ModelUsageAuthResolution? {
        for url in cursorAuthFileURLs {
            if let token = ModelUsageAuthFile.cursorAccessToken(from: url),
               let cookie = ModelUsageSessionCookie.cursor(fromJWT: token) {
                return ModelUsageAuthResolution(
                    credential: .sessionCookie(cookie),
                    source: url.path
                )
            }
        }
        if let token = CursorIDETokenStore.accessToken(databaseURL: cursorStateDatabaseURL),
           let cookie = ModelUsageSessionCookie.cursor(fromJWT: token) {
            return ModelUsageAuthResolution(
                credential: .sessionCookie(cookie),
                source: cursorStateDatabaseURL.path
            )
        }
        if let token = keychain.password(service: "cursor-access-token", account: "cursor-user"),
           let cookie = ModelUsageSessionCookie.cursor(fromJWT: token) {
            return ModelUsageAuthResolution(
                credential: .sessionCookie(cookie),
                source: "keychain:cursor-access-token"
            )
        }
        return nil
    }

    private var openAIAuthFileURLs: [URL] {
        var urls: [URL] = []
        if let raw = environment["CODEX_HOME"], !raw.isEmpty {
            urls.append(URL(fileURLWithPath: raw, isDirectory: true).appendingPathComponent("auth.json"))
        }
        urls.append(homeDirectory.appendingPathComponent(".codex/auth.json"))
        urls.append(homeDirectory.appendingPathComponent(".config/codex/auth.json"))
        return urls
    }

    private var cursorAuthFileURLs: [URL] {
        [
            homeDirectory.appendingPathComponent(".cursor/auth.json"),
            homeDirectory.appendingPathComponent(".config/cursor/auth.json"),
        ]
    }

    private var cursorStateDatabaseURL: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }
}

enum ModelUsageAuthFile {
    struct OpenAI: Equatable, Sendable {
        var accessToken: String
        var accountID: String?
    }

    static func openAI(from url: URL, fileManager: FileManager = .default) -> OpenAI? {
        guard let data = fileManager.contents(atPath: url.path),
              let payload = try? JSONDecoder().decode(OpenAIAuthFilePayload.self, from: data),
              let token = payload.accessToken, !token.isEmpty else {
            return nil
        }
        return OpenAI(accessToken: token, accountID: payload.accountID)
    }

    static func cursorAccessToken(from url: URL, fileManager: FileManager = .default) -> String? {
        guard let data = fileManager.contents(atPath: url.path),
              let payload = try? JSONDecoder().decode(CursorAuthFilePayload.self, from: data) else {
            return nil
        }
        let token = payload.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}

enum ModelUsageSessionCookie {
    static func cursor(fromJWT jwt: String) -> String? {
        guard let userID = JWTUserIdentifier.cursorUserID(from: jwt) else { return nil }
        return "\(userID)%3A%3A\(jwt)"
    }
}

enum JWTUserIdentifier {
    static func cursorUserID(from jwt: String) -> String? {
        guard let payload = decodePayload(jwt),
              let sub = payload["sub"] as? String else {
            return nil
        }
        if let separator = sub.lastIndex(of: "|") {
            let identifier = String(sub[sub.index(after: separator)...])
            return identifier.isEmpty ? sub : identifier
        }
        return sub
    }

    static func decodePayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

enum CursorIDETokenStore {
    static func accessToken(
        databaseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        return queryAccessToken(path: databaseURL.path, uriQuery: "mode=ro")
            ?? queryAccessToken(path: databaseURL.path, uriQuery: "immutable=1")
    }

    private static func queryAccessToken(path: String, uriQuery: String) -> String? {
        var database: OpaquePointer?
        var url = URL(fileURLWithPath: path)
        let items = uriQuery
            .split(separator: "&")
            .compactMap { pair -> URLQueryItem? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let name = parts.first else { return nil }
                return URLQueryItem(name: name, value: parts.count > 1 ? parts[1] : nil)
            }
        url.append(queryItems: items)
        guard sqlite3_open_v2(
            url.absoluteString,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        ) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let pointer = sqlite3_column_text(statement, 0) else { return nil }
        let token = String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

protocol ModelUsageKeychainReading: Sendable {
    func password(service: String, account: String?) -> String?
}

struct ModelUsageKeychainStore: ModelUsageKeychainReading {
    func password(service: String, account: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private struct OpenAIAuthFilePayload: Decodable {
    var tokens: Tokens?
    var rawAccessToken: String?
    var rawAccountID: String?

    struct Tokens: Decodable {
        var accessToken: String?
        var accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tokens
        case rawAccessToken = "access_token"
        case rawAccountID = "account_id"
    }

    var accessToken: String? {
        tokens?.accessToken ?? rawAccessToken
    }

    var accountID: String? {
        tokens?.accountID ?? rawAccountID
    }
}

private struct CursorAuthFilePayload: Decodable {
    var accessToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case token = "access_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decodeIfPresent(String.self, forKey: .token)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
