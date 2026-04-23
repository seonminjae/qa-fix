import Foundation

struct ClaudeVersion: Equatable {
    let raw: String
    let major: Int
    let minor: Int
    let patch: Int

    var isSupported: Bool {
        major > 2 || (major == 2 && minor >= 1)
    }
}

enum ClaudeCodeProbeError: Error, LocalizedError {
    case binaryNotFound
    case launchFailed(Error)
    case exitFailure(Int32, String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "Claude Code CLI binary not found in PATH."
        case .launchFailed(let error): return "Failed to launch claude: \(error.localizedDescription)"
        case .exitFailure(let code, let output): return "claude exited with \(code): \(output)"
        case .parseFailure(let raw): return "Failed to parse claude --version output: \(raw)"
        }
    }
}

struct ClaudeCodeVersionProbe {
    static var candidatePaths: [String] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var paths: [String] = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.nvm/current/bin/claude"
        ]
        // Walk ~/.nvm/versions/node/* and pick every `claude` we find.
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            for version in versions {
                paths.append("\(nvmRoot)/\(version)/bin/claude")
            }
        }
        return paths
    }

    static func resolveBinary() -> URL? {
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return whichClaude()
    }

    private static func whichClaude() -> URL? {
        // Fallback to `/usr/bin/which` which honors PATH env.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        // Ensure common user PATHs are searchable even when Xcode launches us with a sparse env.
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        let injected = [
            "\(NSHomeDirectory())/.nvm/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
        env["PATH"] = existing.isEmpty ? injected : "\(existing):\(injected)"
        which.environment = env
        do {
            try which.run()
        } catch {
            return nil
        }
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty,
              FileManager.default.isExecutableFile(atPath: line) else {
            return nil
        }
        return URL(fileURLWithPath: line)
    }

    static func probe() async throws -> ClaudeVersion {
        guard let binary = resolveBinary() else {
            throw ClaudeCodeProbeError.binaryNotFound
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--version"]
        process.environment = environment(for: binary)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw ClaudeCodeProbeError.launchFailed(error)
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ClaudeCodeProbeError.exitFailure(process.terminationStatus, err.isEmpty ? out : err)
        }
        return try parse(out)
    }

    /// Build a subprocess environment that injects the claude binary's parent directory
    /// (which is where `node` lives for nvm installs) into PATH so the subprocess can
    /// locate its Node runtime. Auth is delegated to Claude Code's own Keychain OAuth.
    static func environment(for binary: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let binDir = binary.deletingLastPathComponent().path
        let existing = env["PATH"] ?? ""
        let extras = [
            binDir,
            "\(NSHomeDirectory())/.nvm/current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let merged = (extras + existing.split(separator: ":").map(String.init))
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let deduped = merged.filter { seen.insert($0).inserted }
        env["PATH"] = deduped.joined(separator: ":")
        return env
    }

    static func parse(_ raw: String) throws -> ClaudeVersion {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ClaudeCodeProbeError.parseFailure(raw)
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 4,
              let majorRange = Range(match.range(at: 1), in: trimmed),
              let minorRange = Range(match.range(at: 2), in: trimmed),
              let patchRange = Range(match.range(at: 3), in: trimmed),
              let major = Int(trimmed[majorRange]),
              let minor = Int(trimmed[minorRange]),
              let patch = Int(trimmed[patchRange])
        else {
            throw ClaudeCodeProbeError.parseFailure(raw)
        }
        return ClaudeVersion(raw: trimmed, major: major, minor: minor, patch: patch)
    }
}
