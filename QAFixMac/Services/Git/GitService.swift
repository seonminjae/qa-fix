import Foundation

enum GitError: Error, LocalizedError {
    case launchFailed(Error)
    case nonZero(Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error): return "git launch failed: \(error.localizedDescription)"
        case .nonZero(let code, let out): return "git exited with \(code): \(out.prefix(200))"
        }
    }
}

struct GitCLIClient {
    static func run(_ args: [String], at cwd: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = cwd
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outString)
                } else {
                    let message = errString.isEmpty ? outString : errString
                    continuation.resume(throwing: GitError.nonZero(proc.terminationStatus, message))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitError.launchFailed(error))
            }
        }
    }

    static func diff(at cwd: URL) async throws -> String {
        try await run(["diff"], at: cwd)
    }

    static func diffNameOnly(at cwd: URL) async throws -> [String] {
        let output = try await run(["diff", "--name-only"], at: cwd)
        return output.split(separator: "\n").map(String.init)
    }

    static func status(at cwd: URL) async throws -> String {
        try await run(["status", "--porcelain"], at: cwd)
    }

    static func commit(message: String, files: [String], at cwd: URL) async throws -> String {
        if !files.isEmpty {
            _ = try await run(["add"] + files, at: cwd)
        }
        return try await run(["commit", "-m", message], at: cwd)
    }

    static func checkoutAll(at cwd: URL) async throws {
        _ = try await run(["checkout", "--", "."], at: cwd)
    }

    static func stashPush(message: String, at cwd: URL) async throws -> String {
        try await run(["stash", "push", "-u", "-m", message], at: cwd)
    }

    static func stashList(at cwd: URL) async throws -> String {
        try await run(["stash", "list"], at: cwd)
    }

    static func stashPop(at cwd: URL) async throws -> String {
        try await run(["stash", "pop"], at: cwd)
    }

    static func headSHA(at cwd: URL) async throws -> String {
        try await run(["rev-parse", "--short", "HEAD"], at: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
