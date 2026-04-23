import Foundation

// Step 2.5: CLI Prototype Spike
//
// Verifies the Claude Code CLI invocation template used by QAFixMac:
//   claude -p --verbose --bare --output-format stream-json ...
//
// What this spike proves (or falsifies):
//   1. `--verbose --bare` together produce stream-json NDJSON on stdout.
//   2. The child process terminates on its own when the prompt is brief.
//   3. We can distinguish stdout (event stream) from stderr (warnings).
//   4. We can detect hook/plugin inheritance is disabled by `--bare`.
//
// Usage:
//   swift run CLISpike [optional-prompt] [optional-repo-path]
//
// If no prompt is provided the spike sends "Reply with the word PONG and nothing else."
// If no repo path is provided the current working directory is used.

@discardableResult
func resolveClaudeBinary() -> URL? {
    let candidates = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.nvm/versions/node/v22.18.0/bin/claude",
        "\(NSHomeDirectory())/.nvm/current/bin/claude"
    ]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    // Fall back to PATH lookup via `which`.
    let which = Process()
    which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    which.arguments = ["claude"]
    let out = Pipe()
    which.standardOutput = out
    which.standardError = Pipe()
    try? which.run()
    which.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    if let line = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !line.isEmpty,
       FileManager.default.isExecutableFile(atPath: line) {
        return URL(fileURLWithPath: line)
    }
    return nil
}

func runSpike(prompt: String, workingDirectory: URL) throws {
    guard let binary = resolveClaudeBinary() else {
        FileHandle.standardError.write(Data("[spike] claude binary not found\n".utf8))
        exit(2)
    }
    FileHandle.standardError.write(Data("[spike] binary: \(binary.path)\n".utf8))
    FileHandle.standardError.write(Data("[spike] cwd:    \(workingDirectory.path)\n".utf8))

    let process = Process()
    process.executableURL = binary
    process.arguments = [
        "-p",
        "--verbose",
        "--output-format", "stream-json",
        "--permission-mode", "bypassPermissions",
        "--add-dir", workingDirectory.path
    ]
    process.currentDirectoryURL = workingDirectory

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    stdinPipe.fileHandleForWriting.write(Data(prompt.utf8))
    try? stdinPipe.fileHandleForWriting.close()

    var eventCount = 0
    var unknownEventCount = 0
    var sawResult = false
    var buffer = Data()

    while process.isRunning {
        let chunk = stdoutPipe.fileHandleForReading.availableData
        if chunk.isEmpty { continue }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newline)
            buffer.removeSubrange(0...newline)
            guard !lineData.isEmpty else { continue }
            eventCount += 1
            if let text = String(data: lineData, encoding: .utf8),
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let type = (json["type"] as? String) ?? "?"
                if type == "result" {
                    sawResult = true
                    let cost = json["total_cost_usd"] as? Double ?? -1
                    let duration = json["duration_ms"] as? Int ?? -1
                    print("[event #\(eventCount)] result (cost=\(cost) USD, duration=\(duration)ms)")
                } else {
                    print("[event #\(eventCount)] \(type)")
                }
            } else {
                unknownEventCount += 1
                if let preview = String(data: lineData.prefix(120), encoding: .utf8) {
                    print("[event #\(eventCount)] <unknown> \(preview)")
                }
            }
        }
    }
    // Drain remaining output.
    let trailing = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    buffer.append(trailing)
    if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
        for line in tail.split(separator: "\n") where !line.isEmpty {
            eventCount += 1
            print("[event #\(eventCount)] (trailing) \(line)")
        }
    }

    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    if !stderrData.isEmpty, let err = String(data: stderrData, encoding: .utf8) {
        FileHandle.standardError.write(Data("[spike stderr]\n\(err)\n".utf8))
    }

    FileHandle.standardError.write(
        Data("[spike] exit=\(process.terminationStatus) events=\(eventCount) unknown=\(unknownEventCount) sawResult=\(sawResult)\n".utf8)
    )
    exit(process.terminationStatus)
}

let args = CommandLine.arguments
let prompt = args.count > 1 ? args[1] : "Reply with the word PONG and nothing else."
let cwd = URL(fileURLWithPath: args.count > 2 ? args[2] : FileManager.default.currentDirectoryPath)

do {
    try runSpike(prompt: prompt, workingDirectory: cwd)
} catch {
    FileHandle.standardError.write(Data("[spike] launch failed: \(error.localizedDescription)\n".utf8))
    exit(3)
}
