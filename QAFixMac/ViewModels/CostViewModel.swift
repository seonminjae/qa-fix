import Foundation

@MainActor
@Observable
final class CostViewModel {
    var totalCostUSD: Double = 0
    var totalInput: Int = 0
    var totalOutput: Int = 0
    var sessionCount: Int = 0
    var sessions: [SessionRecord] = []

    func reload() {
        let store = try? SessionStore()
        let records = store?.list() ?? []
        sessions = records
        totalCostUSD = records.reduce(0) { $0 + $1.cost.totalCostUSD }
        totalInput = records.reduce(0) { $0 + $1.cost.inputTokens }
        totalOutput = records.reduce(0) { $0 + $1.cost.outputTokens }
        sessionCount = records.count
    }
}
