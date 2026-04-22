import SwiftUI

struct QuestionView: View {
    let question: String
    @Binding var answer: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("debugger 질문")
                .font(.headline)
            ScrollView {
                Text(question)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            Text("답변")
                .font(.subheadline)
            TextEditor(text: $answer)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Submit") { onSubmit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
