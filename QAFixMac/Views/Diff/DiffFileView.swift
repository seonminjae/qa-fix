import SwiftUI

struct DiffFileView: View {
    let file: DiffFile

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks, id: \.self) { hunk in
                    Text(hunk.header)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.secondary.opacity(0.1))
                    ForEach(hunk.lines, id: \.self) { line in
                        HStack(spacing: 0) {
                            Text(prefix(line.kind))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 16)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(background(for: line.kind))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func prefix(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        case .meta: return "·"
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.15)
        case .deletion: return Color.red.opacity(0.15)
        case .context, .meta: return Color.clear
        }
    }
}
