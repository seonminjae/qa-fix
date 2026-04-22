import Foundation

final class ClaudeCodeCLIClient: ClaudeCodeService {
    private let stderrContinuationLock = NSLock()
    private var stderrContinuation: AsyncStream<String>.Continuation?
    private var currentProcess: Process?
    private let binaryProvider: () -> URL?

    init(binaryProvider: @escaping () -> URL? = { ClaudeCodeVersionProbe.resolveBinary() }) {
        self.binaryProvider = binaryProvider
    }

    func stderrStream() -> AsyncStream<String> {
        AsyncStream { continuation in
            stderrContinuationLock.lock()
            stderrContinuation = continuation
            stderrContinuationLock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.stderrContinuationLock.lock()
                self?.stderrContinuation = nil
                self?.stderrContinuationLock.unlock()
            }
        }
    }

    func cancelCurrentSession() {
        guard let process = currentProcess, process.isRunning else { return }
        process.interrupt() // SIGINT
        let deadline = DispatchTime.now() + .seconds(2)
        DispatchQueue.global().asyncAfter(deadline: deadline) { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate() // SIGTERM
            let hardDeadline = DispatchTime.now() + .seconds(3)
            DispatchQueue.global().asyncAfter(deadline: hardDeadline) { [weak process] in
                guard let process, process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func runAgent(invocation: ClaudeInvocation) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let binary = binaryProvider() else {
                continuation.finish(throwing: ClaudeClientError.binaryNotFound)
                return
            }
            let args = invocation.command(binary: binary)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())
            process.currentDirectoryURL = invocation.workingDirectory
            process.environment = ClaudeCodeVersionProbe.environment(for: binary)

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let buffer = NDJSONLineBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { return }
                let lines = buffer.append(data)
                for line in lines {
                    let event = StreamJSONParser.parseLine(line)
                    continuation.yield(event)
                    if self == nil { return }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self?.stderrContinuationLock.lock()
                self?.stderrContinuation?.yield(text)
                self?.stderrContinuationLock.unlock()
            }

            process.terminationHandler = { [weak self] proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if let tail = buffer.flush() {
                    continuation.yield(StreamJSONParser.parseLine(tail))
                }
                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    continuation.finish()
                } else if proc.terminationReason == .uncaughtSignal {
                    continuation.finish(throwing: ClaudeClientError.stoppedByUser)
                } else {
                    continuation.finish(throwing: ClaudeClientError.exitedWithError(exitCode, ""))
                }
                if self?.currentProcess === proc {
                    self?.currentProcess = nil
                }
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancelCurrentSession()
            }

            do {
                try process.run()
                self.currentProcess = process
            } catch {
                continuation.finish(throwing: ClaudeClientError.launchFailed(error))
                return
            }

            // Send prompt via stdin and close.
            if let data = invocation.prompt.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()
        }
    }
}
