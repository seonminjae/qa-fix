import Foundation

/// Holds live `AgentViewModel` instances keyed by ticket page ID.
///
/// Owned at the app level so `FixSessionView` state survives tab
/// switches that would otherwise unmount the view and destroy its
/// `@State` view model.
@MainActor
@Observable
final class FixSessionStore {
    private var sessions: [String: AgentViewModel] = [:]

    func viewModel(
        for ticket: Ticket,
        model: String,
        maxBudgetUSD: Double,
        mcpConfigURL: URL?
    ) -> AgentViewModel {
        if let existing = sessions[ticket.pageID] {
            return existing
        }
        let orchestrator = AgentOrchestrator(
            mcpConfigURL: mcpConfigURL,
            model: model,
            maxBudgetUSD: maxBudgetUSD
        )
        let viewModel = AgentViewModel(
            orchestrator: orchestrator,
            mcpConfigURL: mcpConfigURL,
            model: model,
            maxBudgetUSD: maxBudgetUSD
        )
        sessions[ticket.pageID] = viewModel
        return viewModel
    }

    func discard(ticketPageID: String) {
        sessions.removeValue(forKey: ticketPageID)
    }
}
