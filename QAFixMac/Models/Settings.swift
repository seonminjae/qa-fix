import Foundation

enum AnthropicModel: String, CaseIterable, Identifiable, Codable {
    case sonnet4 = "claude-sonnet-4-20250514"
    case sonnet46 = "claude-sonnet-4-6"
    case opus47 = "claude-opus-4-7"
    case haiku45 = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet4: return "Claude Sonnet 4 (default)"
        case .sonnet46: return "Claude Sonnet 4.6"
        case .opus47: return "Claude Opus 4.7"
        case .haiku45: return "Claude Haiku 4.5"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var notionDatabaseID: String
    var repositoryBookmark: Data?
    var model: AnthropicModel
    var maxBudgetUSD: Double

    static let `default` = AppSettings(
        notionDatabaseID: "",
        repositoryBookmark: nil,
        model: .sonnet4,
        maxBudgetUSD: 5.0
    )
}

enum SettingsStoreKey {
    static let notionDatabaseID = "settings.notionDatabaseID"
    static let repositoryBookmark = "settings.repositoryBookmark"
    static let model = "settings.model"
    static let maxBudgetUSD = "settings.maxBudgetUSD"
}
