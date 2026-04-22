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
    static func run(_ args: [String], at cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = cwd
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error)
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outString = String(data: outData, encoding: .utf8) ?? ""
        let errString = String(data: errData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitError.nonZero(process.terminationStatus, errString.isEmpty ? outString : errString)
        }
        return outString
    }

    static func diff(at cwd: URL) throws -> String {
        try run(["diff"], at: cwd)
    }

    static func diffNameOnly(at cwd: URL) throws -> [String] {
        let output = try run(["diff", "--name-only"], at: cwd)
        return output.split(separator: "\n").map(String.init)
    }

    static func status(at cwd: URL) throws -> String {
        try run(["status", "--porcelain"], at: cwd)
    }

    static func commit(message: String, files: [String], at cwd: URL) throws -> String {
        if !files.isEmpty {
            _ = try run(["add"] + files, at: cwd)
        }
        return try run(["commit", "-m", message], at: cwd)
    }

    static func checkoutAll(at cwd: URL) throws {
        _ = try run(["checkout", "--", "."], at: cwd)
    }

    static func stashPush(message: String, at cwd: URL) throws -> String {
        try run(["stash", "push", "-u", "-m", message], at: cwd)
    }

    static func stashList(at cwd: URL) throws -> String {
        try run(["stash", "list"], at: cwd)
    }

    static func stashPop(at cwd: URL) throws -> String {
        try run(["stash", "pop"], at: cwd)
    }

    static func headSHA(at cwd: URL) throws -> String {
        try run(["rev-parse", "--short", "HEAD"], at: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
