import Foundation

@MainActor
@Observable
final class TicketListViewModel {
    var tickets: [Ticket] = []
    var availableVersions: [String] = []
    var selectedVersion: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var selectedTicketID: String?

    private let notion: NotionService

    init(notion: NotionService = NotionAPIClient()) {
        self.notion = notion
    }

    var selectedTicket: Ticket? {
        guard let id = selectedTicketID else { return nil }
        return tickets.first { $0.pageID == id }
    }

    func refresh(databaseID: String) async {
        guard !databaseID.isEmpty else {
            errorMessage = "Configure the Notion database ID in Settings first."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let all = try await notion.fetchOpenedTickets(databaseID: databaseID, version: nil)
            var versions = Set<String>()
            for ticket in all {
                for tag in ticket.versionTags where tag.hasPrefix("iOS") {
                    versions.insert(tag)
                }
            }
            availableVersions = versions.sorted()
            if selectedVersion == nil, let first = availableVersions.first {
                selectedVersion = first
            }
            applyFilter(tickets: all)
            await hydrateComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyFilter(tickets source: [Ticket]) {
        guard let version = selectedVersion else {
            tickets = source
            return
        }
        tickets = source.filter { $0.versionTags.contains(version) }
    }

    private func hydrateComments() async {
        await withTaskGroup(of: (String, [TicketComment]).self) { group in
            for ticket in tickets {
                group.addTask { [notion] in
                    let comments = (try? await notion.fetchComments(pageID: ticket.pageID)) ?? []
                    return (ticket.pageID, comments)
                }
            }
            for await (pageID, comments) in group {
                if let index = tickets.firstIndex(where: { $0.pageID == pageID }) {
                    tickets[index].comments = comments.sorted { $0.createdTime < $1.createdTime }
                }
            }
        }
    }
}
