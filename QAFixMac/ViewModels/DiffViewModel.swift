import Foundation

@MainActor
@Observable
final class DiffViewModel {
    var files: [DiffFile] = []
    var error: String?

    func refresh(repo: URL) async {
        do {
            let diff = try await GitCLIClient.diff(at: repo)
            files = DiffParser.parse(diff)
            error = nil
        } catch {
            self.error = error.localizedDescription
            files = []
        }
    }
}
