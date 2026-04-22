import SwiftUI

struct ActionBarView: View {
    var canAct: Bool
    var isBusy: Bool
    var onCommit: () -> Void
    var onRefix: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack {
            Button(action: onCommit) {
                Label("Commit", systemImage: "checkmark.seal.fill")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!canAct || isBusy)

            Button(action: onRefix) {
                Label("Re-fix", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canAct || isBusy)

            Spacer()

            Button(role: .destructive, action: onCancel) {
                Label("Discard", systemImage: "xmark.octagon")
            }
            .disabled(!canAct || isBusy)

            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(8)
        .background(.thinMaterial)
    }
}
