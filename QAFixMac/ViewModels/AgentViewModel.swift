import Foundation

enum FixSessionStage: String {
    case ready
    case stashCreated
    case agentRunning
    case awaitingUser
    case readyToCommit
    case committing
    case completed
    case failed
}

@MainActor
@Observable
final class AgentViewModel {
    let orchestrator: AgentOrchestrator
    private let notion: NotionService
    private let claude: ClaudeCodeService
    private let mcpConfigURL: URL?
    private let model: String
    private let maxBudgetUSD: Double?
    private let sessionStore: SessionStore?

    var stage: FixSessionStage = .ready
    var stashMessage: String?
    var commitOutput: String = ""
    var diffFiles: [DiffFile] = []
    var question: String = ""
    var answerDraft: String = ""
    var status: String = ""
    var errorMessage: String?
    var currentSession: SessionRecord?

    init(
        orchestrator: AgentOrchestrator,
        notion: NotionService = NotionAPIClient(),
        claude: ClaudeCodeService = ClaudeCodeCLIClient(),
        mcpConfigURL: URL?,
        model: String,
        maxBudgetUSD: Double?
    ) {
        self.orchestrator = orchestrator
        self.notion = notion
        self.claude = claude
        self.mcpConfigURL = mcpConfigURL
        self.model = model
        self.maxBudgetUSD = maxBudgetUSD
        self.sessionStore = try? SessionStore()
    }

    var isBusy: Bool {
        switch stage {
        case .agentRunning, .committing, .stashCreated: return true
        default: return false
        }
    }

    var hasPendingQuestion: Bool { stage == .awaitingUser }

    func start(ticket: Ticket, repo: URL) async {
        errorMessage = nil
        stage = .stashCreated
        var record = SessionRecord.new(ticket: ticket)
        do {
            let stashID = "QAFixMac-\(ticket.displayID)-\(Int(Date().timeIntervalSince1970))"
            let result = try GitCLIClient.stashPush(message: stashID, at: repo)
            stashMessage = stashID
            record.stashMessage = stashID
            status = "stash: \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            status = "stash skipped: \(error.localizedDescription)"
            stashMessage = nil
        }
        currentSession = record
        persist(record)
        stage = .agentRunning
        await orchestrator.run(ticket: ticket, workingDirectory: repo)
        await handleOrchestratorFinish(repo: repo)
    }

    func submitAnswer(ticket: Ticket, repo: URL) async {
        guard !answerDraft.isEmpty else { return }
        let draft = answerDraft
        answerDraft = ""
        question = ""
        stage = .agentRunning
        await orchestrator.submitAnswer(draft, ticket: ticket, workingDirectory: repo)
        await handleOrchestratorFinish(repo: repo)
    }

    func cancel(ticket: Ticket?, repo: URL) async {
        orchestrator.cancel()
        do {
            try GitCLIClient.checkoutAll(at: repo)
            if stashMessage != nil {
                _ = try? GitCLIClient.stashPop(at: repo)
                stashMessage = nil
            }
            status = "변경사항 폐기 완료."
        } catch {
            errorMessage = error.localizedDescription
        }
        finishRecord(status: .cancelled)
        stage = .ready
    }

    func requestRefix(ticket: Ticket, repo: URL, feedback: String) async {
        stage = .agentRunning
        await orchestrator.submitAnswer(feedback, ticket: ticket, workingDirectory: repo)
        await handleOrchestratorFinish(repo: repo)
    }

    func commit(ticket: Ticket, repo: URL) async {
        stage = .committing
        commitOutput = ""
        do {
            try GitCLIClient.run(["add", "-A"], at: repo)
            let invocation = ClaudeInvocation(
                prompt: "Inspect staged changes and create a commit for QA ticket \(ticket.displayID) — \(ticket.title). Return [COMMIT OK] <sha> <subject> on success.",
                systemPrompt: PromptTemplates.commitSystemPrompt(),
                model: model,
                workingDirectory: repo,
                mcpConfigPath: mcpConfigURL,
                maxBudgetUSD: maxBudgetUSD
            )
            var commitCost: Double = 0
            var commitInput = 0
            var commitOutputTokens = 0
            orchestrator.append(.system, "── commit phase started ──")
            for try await event in claude.runAgent(invocation: invocation) {
                switch event {
                case .assistantText(let text):
                    commitOutput += text
                    orchestrator.append(.system, text)
                case .toolUse(let name, let input):
                    orchestrator.append(.toolUse, "\(name) \(input.prefix(200))")
                case .toolResult(let text):
                    orchestrator.append(.toolResult, String(text.prefix(500)))
                case .result(let usage, _):
                    commitCost += usage.totalCostUSD ?? 0
                    commitInput += usage.inputTokens
                    commitOutputTokens += usage.outputTokens
                    if let cost = usage.totalCostUSD {
                        orchestrator.append(.system, String(
                            format: "commit result cost=$%.4f input=%d output=%d",
                            cost, usage.inputTokens, usage.outputTokens
                        ))
                    }
                case .error(let message):
                    orchestrator.append(.error, message)
                default:
                    break
                }
            }
            let sha = (try? GitCLIClient.headSHA(at: repo)) ?? "?"
            status = "commit \(sha) 완료"
            try await notion.patchStatus(pageID: ticket.pageID, statusName: "In progress")
            mergeCommitCost(cost: commitCost, input: commitInput, output: commitOutputTokens)
            finishRecord(status: .completed, commitSHA: sha, repo: repo)
            stage = .completed
        } catch {
            errorMessage = error.localizedDescription
            finishRecord(status: .crashed, repo: repo)
            stage = .failed
        }
    }

    private func handleOrchestratorFinish(repo: URL) async {
        syncCostFromOrchestrator()
        switch orchestrator.phase {
        case .waitingForQuestion:
            question = orchestrator.lastDebuggerOutput
            stage = .awaitingUser
        case .finished:
            await refreshDiff(repo: repo)
            currentSession?.changedFiles = diffFiles.map { $0.path }
            persistCurrent()
            stage = .readyToCommit
        case .failed:
            errorMessage = orchestrator.lastError
            finishRecord(status: .crashed, repo: repo)
            stage = .failed
        default:
            break
        }
    }

    private func refreshDiff(repo: URL) async {
        do {
            let diff = try GitCLIClient.diff(at: repo)
            diffFiles = DiffParser.parse(diff)
        } catch {
            diffFiles = []
            status = "diff read failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session recording

    private func syncCostFromOrchestrator() {
        guard var record = currentSession else { return }
        record.cost = CostRecord(
            totalCostUSD: orchestrator.cumulativeCost,
            inputTokens: orchestrator.cumulativeInputTokens,
            outputTokens: orchestrator.cumulativeOutputTokens,
            refixCount: orchestrator.refixCount
        )
        currentSession = record
        persist(record)
    }

    private func mergeCommitCost(cost: Double, input: Int, output: Int) {
        guard var record = currentSession else { return }
        record.cost = CostRecord(
            totalCostUSD: record.cost.totalCostUSD + cost,
            inputTokens: record.cost.inputTokens + input,
            outputTokens: record.cost.outputTokens + output,
            refixCount: record.cost.refixCount
        )
        currentSession = record
        persist(record)
    }

    private func finishRecord(status: SessionStatus, commitSHA: String? = nil, repo: URL? = nil) {
        guard var record = currentSession else { return }
        record.status = status
        record.endedAt = Date()
        if let commitSHA { record.commitSHA = commitSHA }
        if let repo, record.changedFiles.isEmpty {
            record.changedFiles = (try? GitCLIClient.diffNameOnly(at: repo)) ?? []
        }
        currentSession = record
        persist(record)
    }

    private func persistCurrent() {
        if let record = currentSession { persist(record) }
    }

    private func persist(_ record: SessionRecord) {
        try? sessionStore?.save(record)
    }
}
