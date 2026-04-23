import SwiftUI

struct TicketRowView: View {
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ticket.title)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                NotionChip(text: ticket.severity.rawValue, color: severityColor(ticket.severity))
                ForEach(meaningfulEnvironment, id: \.self) { env in
                    NotionChip(text: env, color: .red.opacity(0.7))
                }
            }

            if let assignee = ticket.assignees.first {
                HStack(spacing: 6) {
                    PersonAvatar(name: assignee)
                    Text(ticket.assignees.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            if !bodyPreview.isEmpty {
                Text(bodyPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(ticket.displayID)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var meaningfulEnvironment: [String] {
        ticket.environment.filter { !isNoise($0) }
    }

    private var bodyPreview: String {
        var parts: [String] = []
        if !ticket.reproduceSteps.isEmpty {
            parts.append("[재현 절차]\n\(ticket.reproduceSteps)")
        }
        if !ticket.reproduceResult.isEmpty {
            parts.append("[재현 결과]\n\(ticket.reproduceResult)")
        }
        return parts.joined(separator: "\n\n")
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        NotionChip(text: severity.rawValue, color: severityColor(severity))
    }
}

struct NotionChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}

struct PersonAvatar: View {
    let name: String

    var body: some View {
        ZStack {
            Circle().fill(avatarColor)
            Text(initial)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(1))
    }

    private var avatarColor: Color {
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let palette: [Color] = [.blue, .teal, .purple, .pink, .orange, .green, .indigo]
        return palette[abs(seed) % palette.count]
    }
}

func severityColor(_ severity: Severity) -> Color {
    switch severity {
    case .critical: return .red
    case .major: return .orange
    case .minor: return .yellow
    case .trivial: return .gray
    case .unknown: return .secondary
    }
}

/// Boilerplate values we don't surface in the UI.
func isNoise(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed == "-" { return true }
    let noise: Set<String> = ["iOS", "Android", "Default", "default"]
    return noise.contains(trimmed)
}
