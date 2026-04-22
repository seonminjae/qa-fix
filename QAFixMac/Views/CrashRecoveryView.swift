import SwiftUI

@MainActor
@Observable
final class CrashRecoveryViewModel {
    var sessions: [SessionRecord] = []
    var statusMessage: String?

    private let store: SessionStore?

    init() {
        self.store = try? SessionStore()
        reload()
    }

    func reload() {
        sessions = store?.crashedSessions() ?? []
    }

    func markResolved(_ record: SessionRecord) {
        guard var updated = sessions.first(where: { $0.id == record.id }) else { return }
        updated.status = .cancelled
        updated.endedAt = Date()
        try? store?.save(updated)
        reload()
        statusMessage = "\(record.ticketDisplayID): marked cancelled"
    }

    func popStash(for record: SessionRecord, repo: URL) {
        guard record.stashMessage != nil else {
            statusMessage = "\(record.ticketDisplayID): no stash to pop"
            return
        }
        do {
            _ = try GitCLIClient.stashPop(at: repo)
            statusMessage = "\(record.ticketDisplayID): stash popped"
        } catch {
            statusMessage = "\(record.ticketDisplayID): pop failed — \(error.localizedDescription)"
        }
    }
}

struct CrashRecoveryView: View {
    @State private var viewModel = CrashRecoveryViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsStoreKey.repositoryBookmark) private var repositoryBookmark: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("복구되지 않은 세션")
                .font(.title2.weight(.semibold))
            Text("앱이 이전에 중단된 fix 세션이 \(viewModel.sessions.count)건 남아있습니다. 레포지토리에 stash가 남아있을 수 있으니 확인하고 처리하세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            if viewModel.sessions.isEmpty {
                Text("남은 세션이 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.sessions) { session in
                            row(session)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            if let message = viewModel.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
    }

    private func row(_ session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(session.ticketDisplayID) — \(session.ticketTitle)")
                    .font(.headline)
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stash = session.stashMessage {
                Text("stash: \(stash)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Mark resolved") {
                    viewModel.markResolved(session)
                }
                if session.stashMessage != nil, resolvedRepo() != nil {
                    Button("Pop stash") {
                        if let repo = resolvedRepo() {
                            viewModel.popStash(for: session, repo: repo)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func resolvedRepo() -> URL? {
        guard let bookmark = repositoryBookmark,
              let url = try? BookmarkManager.resolve(bookmark) else { return nil }
        _ = BookmarkManager.startAccess(url)
        return url
    }
}
