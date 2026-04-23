import SwiftUI

struct TicketDetailView: View {
    let ticket: Ticket

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                essentials
                if !ticket.reproduceSteps.isEmpty || !ticket.reproduceResult.isEmpty {
                    reproduceSection
                }
                if !ticket.attachments.isEmpty {
                    attachmentsSection
                }
                if !ticket.comments.isEmpty {
                    commentsSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SeverityBadge(severity: ticket.severity)
                if !ticket.status.isEmpty, ticket.status != "-" {
                    NotionChip(text: ticket.status, color: statusColor(ticket.status))
                }
                ForEach(visibleEnvironment, id: \.self) { env in
                    NotionChip(text: env, color: .red.opacity(0.7))
                }
                Spacer()
                Text(ticket.displayID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(ticket.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var essentials: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("담당자") {
                PersonRow(names: ticket.assignees)
            }
            if !ticket.reporter.isEmpty {
                row("보고자") {
                    PersonRow(names: ticket.reporter)
                }
            }
            if !ticket.device.isEmpty {
                row("확인 Device") {
                    Text(ticket.device)
                        .textSelection(.enabled)
                }
            }
            if !ticket.affectedVersion.isEmpty {
                row("발생 버전") {
                    Text(ticket.affectedVersion)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var reproduceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !ticket.reproduceSteps.isEmpty {
                section("재현 절차", body: ticket.reproduceSteps)
            }
            if !ticket.reproduceResult.isEmpty {
                section("재현 결과", body: ticket.reproduceResult)
            }
        }
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var visibleEnvironment: [String] {
        ticket.environment.filter { !isNoise($0) }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("첨부").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                ForEach(ticket.attachments) { attachment in
                    if let url = URL(string: attachment.url) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let image): image.resizable().scaledToFit()
                            case .failure: Image(systemName: "photo")
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(height: 120)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("댓글").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(ticket.comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(comment.author) • \(comment.createdTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comment.text)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct PersonRow: View {
    let names: [String]

    var body: some View {
        if names.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 4) {
                        PersonAvatar(name: name)
                        Text(name)
                    }
                }
            }
        }
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "Opened": return .red.opacity(0.7)
    case "In progress": return .blue
    case "Closed": return .green
    case "Rejected": return .gray
    default: return .secondary
    }
}
