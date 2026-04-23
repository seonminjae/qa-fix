import Foundation

@MainActor
@Observable
final class TicketListViewModel {
    var tickets: [Ticket] = []
    var availableVersions: [String] = []
    var selectedVersion: String? {
        didSet {
            guard oldValue != selectedVersion else { return }
            applyFilter()
        }
    }
    var isLoading: Bool = false
    var errorMessage: String?
    var selectedTicketID: String?

    private var allTickets: [Ticket] = []
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
            let platforms = PlatformSettings.load()
            let scoped = all.filter { Self.matchesPlatforms($0, platforms: platforms) }
            var versions = Set<String>()
            for ticket in scoped {
                for tag in ticket.versionTags {
                    versions.insert(tag)
                }
            }
            availableVersions = versions.sorted()
            allTickets = scoped
            if let current = selectedVersion, !availableVersions.contains(current) {
                selectedVersion = availableVersions.first
            } else if selectedVersion == nil, let first = availableVersions.first {
                selectedVersion = first
            } else {
                applyFilter()
            }
            await hydrateComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func matchesPlatforms(_ ticket: Ticket, platforms: Set<Platform>) -> Bool {
        guard !platforms.isEmpty else { return true }
        let selected = Set(platforms.map { $0.rawValue })
        return ticket.environment.contains { selected.contains($0) }
    }

    func applyFilter() {
        guard let version = selectedVersion else {
            tickets = allTickets
            return
        }
        tickets = allTickets.filter { $0.versionTags.contains(version) }
    }

    private func hydrateComments() async {
        await withTaskGroup(of: (String, [TicketComment]).self) { group in
            for ticket in allTickets {
                group.addTask { [notion] in
                    let comments = (try? await notion.fetchComments(pageID: ticket.pageID)) ?? []
                    return (ticket.pageID, comments)
                }
            }
            for await (pageID, comments) in group {
                if let index = allTickets.firstIndex(where: { $0.pageID == pageID }) {
                    allTickets[index].comments = comments.sorted { $0.createdTime < $1.createdTime }
                }
            }
            applyFilter()
        }
    }
}
