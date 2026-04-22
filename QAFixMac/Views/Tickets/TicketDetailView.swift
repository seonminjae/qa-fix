import SwiftUI

struct TicketDetailView: View {
    let ticket: Ticket

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                reproduceSection
                if !ticket.attachments.isEmpty {
                    Divider()
                    attachmentsSection
                }
                if !ticket.comments.isEmpty {
                    Divider()
                    commentsSection
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SeverityBadge(severity: ticket.severity)
                Text(ticket.displayID)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Text(ticket.title)
                .font(.title2.weight(.semibold))
            if !ticket.assignees.isEmpty {
                Text("Assignees: \(ticket.assignees.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Affected version: \(ticket.affectedVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var reproduceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("재현 절차").font(.headline)
            Text(ticket.reproduceSteps.isEmpty ? "—" : ticket.reproduceSteps)
                .textSelection(.enabled)
            Text("재현 결과").font(.headline).padding(.top, 6)
            Text(ticket.reproduceResult.isEmpty ? "—" : ticket.reproduceResult)
                .textSelection(.enabled)
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("첨부").font(.headline)
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
            Text("댓글").font(.headline)
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
