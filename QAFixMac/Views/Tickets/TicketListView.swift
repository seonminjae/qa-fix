import SwiftUI

struct TicketListView: View {
    @State private var viewModel = TicketListViewModel()
    @State private var scopedRepo: URL?
    @AppStorage(SettingsStoreKey.notionDatabaseID) private var databaseID: String = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 300)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            resolveRepoIfNeeded()
            if viewModel.tickets.isEmpty {
                await viewModel.refresh(databaseID: databaseID)
            }
        }
        .onDisappear {
            releaseRepo()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Version", selection: Binding(
                    get: { viewModel.selectedVersion ?? "" },
                    set: { viewModel.selectedVersion = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All").tag("")
                    ForEach(viewModel.availableVersions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button(action: { Task { await viewModel.refresh(databaseID: databaseID) } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(8)
            if viewModel.isLoading {
                ProgressView().padding()
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }
            List(viewModel.tickets, selection: $viewModel.selectedTicketID) { ticket in
                TicketRowView(ticket: ticket).tag(ticket.pageID as String?)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let ticket = viewModel.selectedTicket, let repo = scopedRepo {
            FixSessionView(ticket: ticket, repo: repo)
                .id(ticket.pageID)
        } else if viewModel.selectedTicket != nil {
            placeholder("Select a repository path in Settings.")
        } else {
            placeholder("Select a ticket")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolveRepoIfNeeded() {
        guard scopedRepo == nil else { return }
        guard let bookmark = UserDefaults.standard.data(forKey: SettingsStoreKey.repositoryBookmark) else {
            return
        }
        guard let url = try? BookmarkManager.resolve(bookmark) else { return }
        if BookmarkManager.startAccess(url) {
            scopedRepo = url
        }
    }

    private func releaseRepo() {
        if let url = scopedRepo {
            BookmarkManager.stopAccess(url)
            scopedRepo = nil
        }
    }
}
