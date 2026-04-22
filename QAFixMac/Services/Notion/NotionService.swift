import Foundation

protocol NotionService: AnyObject {
    func fetchOpenedTickets(databaseID: String, version: String?) async throws -> [Ticket]
    func fetchComments(pageID: String) async throws -> [TicketComment]
    func fetchImageBlocks(pageID: String) async throws -> [String]
    func patchStatus(pageID: String, statusName: String) async throws
}

enum NotionError: Error, LocalizedError {
    case missingToken
    case httpError(Int, String)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Notion integration token is missing."
        case .httpError(let code, let body): return "Notion HTTP \(code): \(body.prefix(200))"
        case .decoding(let error): return "Notion decoding failed: \(error.localizedDescription)"
        case .network(let error): return "Notion network error: \(error.localizedDescription)"
        }
    }
}
