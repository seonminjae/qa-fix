import Foundation

enum MCPConfigError: Error, LocalizedError {
    case supportDirectoryUnavailable
    case encodingFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .supportDirectoryUnavailable: return "Application Support directory unavailable."
        case .encodingFailed(let error): return "MCP config encoding failed: \(error.localizedDescription)"
        case .writeFailed(let error): return "MCP config write failed: \(error.localizedDescription)"
        }
    }
}

struct MCPConfigManager {
    static let supportDirectoryName = "QAFixMac"
    static let mcpConfigFileName = "mcp.json"

    static func configFileURL() throws -> URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MCPConfigError.supportDirectoryUnavailable
        }
        let dir = base.appendingPathComponent(supportDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(mcpConfigFileName, isDirectory: false)
    }

    static func writeNotionConfig(token: String) throws -> URL {
        let url = try configFileURL()
        let payload = NotionMCPConfig(token: token)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw MCPConfigError.encodingFailed(error)
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw MCPConfigError.writeFailed(error)
        }
        return url
    }
}

private struct NotionMCPConfig: Encodable {
    let mcpServers: [String: Server]

    init(token: String) {
        mcpServers = [
            "notion": Server(
                command: "npx",
                args: ["-y", "@notionhq/notion-mcp-server"],
                env: ["OPENAPI_MCP_HEADERS": "{\"Authorization\": \"Bearer \(token)\", \"Notion-Version\": \"2022-06-28\"}"]
            )
        ]
    }

    struct Server: Encodable {
        let command: String
        let args: [String]
        let env: [String: String]
    }
}
