import Foundation

enum SessionStatus: String, Codable {
    case inProgress = "in_progress"
    case completed
    case crashed
    case cancelled
}

struct CostRecord: Codable, Hashable {
    var totalCostUSD: Double
    var inputTokens: Int
    var outputTokens: Int
    var refixCount: Int
}

struct SessionRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var ticketDisplayID: String
    var ticketTitle: String
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var stashMessage: String?
    var commitSHA: String?
    var changedFiles: [String]
    var cost: CostRecord

    static func new(ticket: Ticket) -> SessionRecord {
        SessionRecord(
            id: UUID(),
            ticketDisplayID: ticket.displayID,
            ticketTitle: ticket.title,
            startedAt: Date(),
            endedAt: nil,
            status: .inProgress,
            stashMessage: nil,
            commitSHA: nil,
            changedFiles: [],
            cost: CostRecord(totalCostUSD: 0, inputTokens: 0, outputTokens: 0, refixCount: 0)
        )
    }
}

final class SessionStore {
    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() throws {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MCPConfigError.supportDirectoryUnavailable
        }
        let dir = base.appendingPathComponent("QAFixMac/sessions", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.directory = dir
    }

    func save(_ record: SessionRecord) throws {
        let data = try encoder.encode(record)
        let url = directory.appendingPathComponent("\(record.id.uuidString).json")
        try data.write(to: url, options: [.atomic])
    }

    func list() -> [SessionRecord] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SessionRecord.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    func crashedSessions() -> [SessionRecord] {
        list().filter { $0.status == .inProgress }
    }
}
