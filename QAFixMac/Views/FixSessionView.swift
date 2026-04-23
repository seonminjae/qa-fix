import SwiftUI

struct FixSessionView: View {
    let ticket: Ticket
    let repo: URL

    @AppStorage(SettingsStoreKey.model) private var modelRaw: String = AnthropicModel.sonnet4.rawValue
    @AppStorage(SettingsStoreKey.maxBudgetUSD) private var maxBudgetUSD: Double = 5.0

    @State private var viewModel: AgentViewModel

    init(ticket: Ticket, repo: URL) {
        self.ticket = ticket
        self.repo = repo
        let model = (AnthropicModel(rawValue: UserDefaults.standard.string(forKey: SettingsStoreKey.model) ?? "") ?? .sonnet4).rawValue
        let mcp = try? MCPConfigManager.configFileURL()
        let budget = UserDefaults.standard.object(forKey: SettingsStoreKey.maxBudgetUSD) == nil
            ? 5.0 : UserDefaults.standard.double(forKey: SettingsStoreKey.maxBudgetUSD)
        let orchestrator = AgentOrchestrator(
            mcpConfigURL: mcp,
            model: model,
            maxBudgetUSD: budget
        )
        _viewModel = State(
            initialValue: AgentViewModel(
                orchestrator: orchestrator,
                mcpConfigURL: mcp,
                model: model,
                maxBudgetUSD: budget
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ticketHeader
            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Agent Log")
                        .font(.subheadline)
                        .padding(.top, 6)
                        .padding(.horizontal, 8)
                    AgentLogView(log: viewModel.orchestrator.log)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Diff")
                        .font(.subheadline)
                        .padding(.top, 6)
                        .padding(.horizontal, 8)
                    if viewModel.diffFiles.isEmpty {
                        Text("No changes yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        DiffView(files: viewModel.diffFiles)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            if viewModel.hasPendingQuestion {
                Divider()
                QuestionView(
                    question: viewModel.question,
                    answer: $viewModel.answerDraft,
                    onSubmit: { Task { await viewModel.submitAnswer(ticket: ticket, repo: repo) } },
                    onCancel: { Task { await viewModel.cancel(ticket: ticket, repo: repo) } }
                )
            } else if viewModel.stage == .readyToCommit || viewModel.stage == .failed {
                Divider()
                ActionBarView(
                    canAct: viewModel.stage == .readyToCommit,
                    isBusy: viewModel.isBusy,
                    onCommit: { Task { await viewModel.commit(ticket: ticket, repo: repo) } },
                    onRefix: {
                        viewModel.answerDraft = ""
                        viewModel.stage = .awaitingUser
                        viewModel.question = "추가로 반영해야 할 수정 방향을 입력하세요."
                    },
                    onCancel: { Task { await viewModel.cancel(ticket: ticket, repo: repo) } }
                )
            }

            if let error = viewModel.errorMessage {
                Divider()
                Text(error).foregroundStyle(.red).padding(8)
            } else if !viewModel.status.isEmpty {
                Divider()
                Text(viewModel.status).foregroundStyle(.secondary).font(.caption).padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ticketHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SeverityBadge(severity: ticket.severity)
                ForEach(visibleEnvironment, id: \.self) { env in
                    NotionChip(text: env, color: .red.opacity(0.7))
                }
                Spacer()
                Text(ticket.displayID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if viewModel.isBusy {
                    Button(role: .destructive) {
                        Task { await viewModel.cancel(ticket: ticket, repo: repo) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("에이전트 실행을 중단하고 변경사항을 폐기합니다.")
                } else {
                    Button {
                        Task { await viewModel.start(ticket: ticket, repo: repo) }
                    } label: {
                        Label("Start Fix", systemImage: "play.fill")
                    }
                    .disabled(viewModel.stage != .ready && viewModel.stage != .failed)
                }
            }

            Text(ticket.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                if !ticket.assignees.isEmpty {
                    inlineField("담당자") {
                        HStack(spacing: 4) {
                            PersonAvatar(name: ticket.assignees.first ?? "?")
                            Text(ticket.assignees.joined(separator: ", "))
                        }
                    }
                }
                if !ticket.device.isEmpty {
                    inlineField("디바이스") { Text(ticket.device) }
                }
                if !ticket.affectedVersion.isEmpty {
                    inlineField("발생 버전") { Text(ticket.affectedVersion) }
                }
            }
            .font(.caption)

            if !ticket.reproduceSteps.isEmpty {
                reproduceBlock(title: "재현 절차", body: ticket.reproduceSteps)
            }
            if !ticket.reproduceResult.isEmpty {
                reproduceBlock(title: "재현 결과", body: ticket.reproduceResult)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func inlineField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func reproduceBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibleEnvironment: [String] {
        ticket.environment.filter { !isNoise($0) }
    }
}
