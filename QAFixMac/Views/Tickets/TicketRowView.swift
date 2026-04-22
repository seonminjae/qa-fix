import SwiftUI

struct TicketRowView: View {
    let ticket: Ticket

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SeverityBadge(severity: ticket.severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.title)
                    .lineLimit(1)
                Text("\(ticket.displayID) • \(ticket.affectedVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !ticket.assignees.isEmpty {
                Text(ticket.assignees.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch severity {
        case .critical: return .red
        case .major: return .orange
        case .minor: return .yellow
        case .trivial: return .gray
        case .unknown: return .secondary
        }
    }
}
