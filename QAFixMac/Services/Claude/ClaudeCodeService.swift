import Foundation

struct ClaudeInvocation {
    var prompt: String
    var systemPrompt: String?
    var model: String
    var workingDirectory: URL
    var mcpConfigPath: URL?
    var maxBudgetUSD: Double?

    func command(binary: URL) -> [String] {
        var args: [String] = [
            binary.path,
            "-p",
            "--verbose",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--permission-mode", "bypassPermissions",
            "--model", model,
            "--add-dir", workingDirectory.path
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            args.append(contentsOf: ["--system-prompt", systemPrompt])
        }
        if let mcpConfigPath {
            args.append(contentsOf: ["--mcp-config", mcpConfigPath.path])
        }
        if let maxBudgetUSD {
            args.append(contentsOf: ["--max-budget-usd", String(format: "%.4f", maxBudgetUSD)])
        }
        return args
    }
}

protocol ClaudeCodeService: AnyObject {
    func runAgent(invocation: ClaudeInvocation) -> AsyncThrowingStream<ClaudeStreamEvent, Error>
    func stderrStream() -> AsyncStream<String>
    func cancelCurrentSession()
}

enum ClaudeClientError: Error, LocalizedError {
    case binaryNotFound
    case launchFailed(Error)
    case stoppedByUser
    case exitedWithError(Int32, String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "Claude Code CLI binary not found."
        case .launchFailed(let error): return "Launch failed: \(error.localizedDescription)"
        case .stoppedByUser: return "Session cancelled by user."
        case .exitedWithError(let code, let output):
            return "Claude exited with \(code). \(output.prefix(200))"
        }
    }
}
