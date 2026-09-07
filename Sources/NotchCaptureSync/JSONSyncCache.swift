import Foundation

public enum SyncMutation: Codable, Equatable, Sendable {
    case upsert(CaptureRecord)
    case delete(id: UUID, updatedAt: Date)

    public var id: UUID {
        switch self {
        case let .upsert(record): record.id
        case let .delete(id, _): id
        }
    }
}

struct JSONSyncCache: Sendable {
    private struct CacheEnvelope: Codable {
        var version = 1
        var records: [CaptureRecord]
    }

    private struct OutboxEnvelope: Codable {
        var version = 1
        var mutations: [SyncMutation]
    }

    let cacheURL: URL
    let outboxURL: URL

    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        let basename = cacheURL.deletingPathExtension().lastPathComponent
        self.outboxURL = cacheURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(basename)-outbox.json")
    }

    func loadRecords() throws -> [CaptureRecord] {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return [] }
        return try decoder.decode(CacheEnvelope.self, from: Data(contentsOf: cacheURL)).records
    }

    func saveRecords(_ records: [CaptureRecord]) throws {
        try write(CacheEnvelope(records: records), to: cacheURL)
    }

    func loadOutbox() throws -> [SyncMutation] {
        guard FileManager.default.fileExists(atPath: outboxURL.path) else { return [] }
        return try decoder.decode(OutboxEnvelope.self, from: Data(contentsOf: outboxURL)).mutations
    }

    func saveOutbox(_ mutations: [SyncMutation]) throws {
        try write(OutboxEnvelope(mutations: mutations), to: outboxURL)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
