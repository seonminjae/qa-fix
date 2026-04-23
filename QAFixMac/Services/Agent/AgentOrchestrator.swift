import Foundation

enum AgentPhase: String {
    case idle
    case debuggerRunning = "debugger"
    case verifierRunning = "verifier"
    case waitingForQuestion = "question"
    case finished
    case failed
}

enum DebuggerOutcome {
    case question(body: String)
    case fixed(body: String)
    case inconclusive(body: String)
}

enum VerifierOutcome {
    case pass(body: String)
    case refix(body: String)
    case inconclusive(body: String)
}

struct AgentLogEntry: Identifiable {
    enum Source: String { case system, debugger, verifier, toolUse, toolResult, error, user }

    let id = UUID()
    let timestamp: Date
    let source: Source
    let text: String
}

@MainActor
@Observable
final class AgentOrchestrator {
    private let service: ClaudeCodeService
    private let mcpConfigURL: URL?
    private let model: String
    private let maxBudgetUSD: Double?

    var phase: AgentPhase = .idle
    var log: [AgentLogEntry] = []
    var cumulativeCost: Double = 0
    var cumulativeInputTokens: Int = 0
    var cumulativeOutputTokens: Int = 0
    var lastDebuggerOutput: String = ""
    var lastVerifierOutput: String = ""
    var lastError: String?
    var refixCount: Int = 0
    var maxRefix: Int = 3

    init(
        service: ClaudeCodeService = ClaudeCodeCLIClient(),
        mcpConfigURL: URL? = nil,
        model: String = AnthropicModel.opus46.rawValue,
        maxBudgetUSD: Double? = nil
    ) {
        self.service = service
        self.mcpConfigURL = mcpConfigURL
        self.model = model
        self.maxBudgetUSD = maxBudgetUSD
    }

    func cancel() {
        service.cancelCurrentSession()
        phase = .idle
    }

    func run(ticket: Ticket, workingDirectory: URL) async {
        reset()
        await runDebugger(ticket: ticket, workingDirectory: workingDirectory, previousFeedback: nil)
    }

    func submitAnswer(_ answer: String, ticket: Ticket, workingDirectory: URL) async {
        append(.user, answer)
        await runDebugger(ticket: ticket, workingDirectory: workingDirectory, previousFeedback: "유저 응답:\n\(answer)")
    }

    private func reset() {
        log.removeAll()
        cumulativeCost = 0
        cumulativeInputTokens = 0
        cumulativeOutputTokens = 0
        lastDebuggerOutput = ""
        lastVerifierOutput = ""
        lastError = nil
        refixCount = 0
        phase = .idle
    }

    private func runDebugger(ticket: Ticket, workingDirectory: URL, previousFeedback: String?) async {
        phase = .debuggerRunning
        lastDebuggerOutput = ""
        let invocation = ClaudeInvocation(
            prompt: PromptTemplates.debuggerUserPrompt(ticket: ticket, previousFeedback: previousFeedback),
            systemPrompt: PromptTemplates.debuggerSystemPrompt,
            model: model,
            workingDirectory: workingDirectory,
            mcpConfigPath: mcpConfigURL,
            maxBudgetUSD: maxBudgetUSD
        )
        let outcome = await consume(invocation: invocation, source: .debugger)
        switch outcome {
        case .failure(let message):
            lastError = message
            phase = .failed
            append(.error, message)
        case .success(let accumulated):
            lastDebuggerOutput = accumulated
            let parsed = parseDebugger(accumulated)
            switch parsed {
            case .question:
                phase = .waitingForQuestion
            case .fixed:
                await runVerifier(ticket: ticket, workingDirectory: workingDirectory)
            case .inconclusive(let body):
                lastError = "Debugger did not produce a terminal keyword: \(body.prefix(200))"
                phase = .failed
            }
        }
    }

    private func runVerifier(ticket: Ticket, workingDirectory: URL) async {
        phase = .verifierRunning
        lastVerifierOutput = ""
        let gitDiff = (try? await GitCLIClient.diff(at: workingDirectory)) ?? "(git diff 실행 실패)"
        let invocation = ClaudeInvocation(
            prompt: PromptTemplates.verifierUserPrompt(
                ticket: ticket,
                debuggerOutput: lastDebuggerOutput,
                gitDiff: gitDiff
            ),
            systemPrompt: PromptTemplates.verifierSystemPrompt,
            model: model,
            workingDirectory: workingDirectory,
            mcpConfigPath: mcpConfigURL,
            maxBudgetUSD: maxBudgetUSD
        )
        let outcome = await consume(invocation: invocation, source: .verifier)
        switch outcome {
        case .failure(let message):
            lastError = message
            phase = .failed
        case .success(let accumulated):
            lastVerifierOutput = accumulated
            let parsed = parseVerifier(accumulated)
            switch parsed {
            case .pass:
                phase = .finished
            case .refix(let body):
                if refixCount < maxRefix {
                    refixCount += 1
                    await runDebugger(ticket: ticket, workingDirectory: workingDirectory, previousFeedback: body)
                } else {
                    phase = .finished
                    append(.system, "재수정 루프가 최대 \(maxRefix)회에 도달했습니다.")
                }
            case .inconclusive(let body):
                lastError = "Verifier did not produce a terminal keyword: \(body.prefix(200))"
                phase = .failed
            }
        }
    }

    private enum ConsumeResult {
        case success(String)
        case failure(String)
    }

    private func consume(invocation: ClaudeInvocation, source: AgentLogEntry.Source) async -> ConsumeResult {
        var accumulated = ""
        do {
            for try await event in service.runAgent(invocation: invocation) {
                switch event {
                case .assistantText(let text):
                    accumulated += text
                    append(source, text)
                case .toolUse(let name, let input):
                    append(.toolUse, "\(name) \(input.prefix(200))")
                case .toolResult(let text):
                    append(.toolResult, String(text.prefix(500)))
                case .result(let usage, _):
                    cumulativeCost += usage.totalCostUSD ?? 0
                    cumulativeInputTokens += usage.inputTokens
                    cumulativeOutputTokens += usage.outputTokens
                    if let cost = usage.totalCostUSD {
                        append(.system, String(format: "result cost=$%.4f input=%d output=%d",
                                               cost, usage.inputTokens, usage.outputTokens))
                    }
                case .error(let message):
                    return .failure(message)
                case .rateLimit:
                    append(.system, "rate-limit event received")
                case .system, .unknown:
                    continue
                }
            }
            return .success(accumulated)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func append(_ source: AgentLogEntry.Source, _ text: String) {
        log.append(AgentLogEntry(timestamp: Date(), source: source, text: text))
    }

    private func parseDebugger(_ text: String) -> DebuggerOutcome {
        let head = Self.leadingNonEmptyLines(text, limit: 5)
        if head.contains(where: { $0.contains("[질문 필요]") }) { return .question(body: text) }
        if head.contains(where: { $0.contains("[수정 완료]") }) { return .fixed(body: text) }
        return .inconclusive(body: text)
    }

    private func parseVerifier(_ text: String) -> VerifierOutcome {
        let head = Self.leadingNonEmptyLines(text, limit: 5)
        if head.contains(where: { $0.contains("[통과]") }) { return .pass(body: text) }
        if head.contains(where: { $0.contains("[재수정 필요]") }) { return .refix(body: text) }
        return .inconclusive(body: text)
    }

    private static func leadingNonEmptyLines(_ text: String, limit: Int) -> [String] {
        var result: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            result.append(trimmed)
            if result.count >= limit { break }
        }
        return result
    }
}
