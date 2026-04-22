import SwiftUI
import AppKit

struct AgentLogView: View {
    let log: [AgentLogEntry]

    @State private var justCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollBody
        }
        .background(Color.secondary.opacity(0.05))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(log.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if justCopied {
                Text("Copied ✓")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Button {
                copyAllToPasteboard()
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .help("Copy entire log to clipboard")
            .disabled(log.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(log) { entry in
                        entryRow(entry)
                            .id(entry.id)
                            .contextMenu {
                                Button("Copy line") { copy(entry.text) }
                                Button("Copy from this line") { copyFrom(entry.id) }
                                Divider()
                                Button("Copy all") { copyAllToPasteboard() }
                            }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onChange(of: log.count) { _, _ in
                if let last = log.last?.id {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AgentLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.source.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(color(for: entry.source))
            Text(entry.text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
    }

    private func color(for source: AgentLogEntry.Source) -> Color {
        switch source {
        case .debugger: return .blue
        case .verifier: return .green
        case .toolUse: return .purple
        case .toolResult: return .orange
        case .error: return .red
        case .user: return .pink
        case .system: return .secondary
        }
    }

    // MARK: - Copy helpers

    private func copyAllToPasteboard() {
        let text = log.map(formatEntry).joined(separator: "\n")
        copy(text)
    }

    private func copyFrom(_ id: UUID) {
        guard let index = log.firstIndex(where: { $0.id == id }) else { return }
        let text = log[index...].map(formatEntry).joined(separator: "\n")
        copy(text)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { justCopied = false }
        }
    }

    private func formatEntry(_ entry: AgentLogEntry) -> String {
        let timestamp = ISO8601DateFormatter.string(from: entry.timestamp,
                                                    timeZone: .current,
                                                    formatOptions: [.withInternetDateTime])
        return "[\(timestamp)] \(entry.source.rawValue.uppercased()): \(entry.text)"
    }
}
