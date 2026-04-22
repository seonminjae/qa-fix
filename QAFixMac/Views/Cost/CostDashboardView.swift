import SwiftUI

struct CostDashboardView: View {
    @State private var viewModel = CostViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Cumulative usage") {
                    LabeledContent("Sessions", value: "\(viewModel.sessionCount)")
                    LabeledContent("Input tokens", value: "\(viewModel.totalInput)")
                    LabeledContent("Output tokens", value: "\(viewModel.totalOutput)")
                    LabeledContent("Total cost", value: String(format: "$%.4f", viewModel.totalCostUSD))
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 220)

            Divider()

            HStack {
                Text("Recent sessions").font(.headline)
                Spacer()
                Button(action: { viewModel.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if viewModel.sessions.isEmpty {
                Text("No sessions recorded yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Table(viewModel.sessions) {
                    TableColumn("Ticket") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.ticketDisplayID).font(.body.monospaced())
                            Text(row.ticketTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 180, ideal: 220)

                    TableColumn("Status") { row in
                        StatusPill(status: row.status)
                    }
                    .width(110)

                    TableColumn("Started") { row in
                        Text(row.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                    .width(160)

                    TableColumn("Cost") { row in
                        Text(String(format: "$%.4f", row.cost.totalCostUSD))
                            .font(.body.monospacedDigit())
                    }
                    .width(80)

                    TableColumn("Tokens (in/out)") { row in
                        Text("\(row.cost.inputTokens) / \(row.cost.outputTokens)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(120)

                    TableColumn("Refix") { row in
                        Text("\(row.cost.refixCount)")
                            .font(.body.monospacedDigit())
                    }
                    .width(50)

                    TableColumn("Commit") { row in
                        Text(row.commitSHA ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(80)
                }
            }
        }
        .padding()
        .task { viewModel.reload() }
    }
}

private struct StatusPill: View {
    let status: SessionStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

private extension SessionStatus {
    var displayLabel: String {
        switch self {
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .crashed:    return "Crashed"
        case .cancelled:  return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .inProgress: return .orange
        case .completed:  return .green
        case .crashed:    return .red
        case .cancelled:  return .gray
        }
    }
}

#Preview {
    CostDashboardView()
}
