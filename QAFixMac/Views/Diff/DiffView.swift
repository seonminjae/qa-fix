import SwiftUI

struct DiffView: View {
    let files: [DiffFile]
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            List(files, selection: $selection) { file in
                VStack(alignment: .leading) {
                    Text(file.path).font(.caption).lineLimit(1)
                    HStack {
                        Text("+\(file.additions)").foregroundStyle(.green).font(.caption2)
                        Text("-\(file.deletions)").foregroundStyle(.red).font(.caption2)
                    }
                }
                .tag(file.id as UUID?)
            }
            .frame(minWidth: 180, idealWidth: 240)

            detail
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let file = files.first(where: { $0.id == id }) {
            DiffFileView(file: file)
        } else if let first = files.first {
            DiffFileView(file: first)
        } else {
            Text("No changes")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
