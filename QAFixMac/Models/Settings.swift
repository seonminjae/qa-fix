import Foundation

enum Platform: String, CaseIterable, Identifiable, Codable, Hashable {
    case iOS = "iOS"
    case android = "Android"
    case backend = "backend"
    case web = "Web"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum AnthropicModel: String, CaseIterable, Identifiable, Codable {
    case opus46 = "claude-opus-4-6"
    case opus47 = "claude-opus-4-7"
    case sonnet46 = "claude-sonnet-4-6"
    case haiku45 = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus46: return "Claude Opus 4.6 (default)"
        case .opus47: return "Claude Opus 4.7"
        case .sonnet46: return "Claude Sonnet 4.6"
        case .haiku45: return "Claude Haiku 4.5"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var notionDatabaseID: String
    var repositoryBookmark: Data?
    var model: AnthropicModel
    var maxBudgetUSD: Double
    var platforms: Set<Platform>

    static let `default` = AppSettings(
        notionDatabaseID: "",
        repositoryBookmark: nil,
        model: .opus46,
        maxBudgetUSD: 5.0,
        platforms: []
    )
}

enum SettingsStoreKey {
    static let notionDatabaseID = "settings.notionDatabaseID"
    static let repositoryBookmark = "settings.repositoryBookmark"
    static let model = "settings.model"
    static let maxBudgetUSD = "settings.maxBudgetUSD"
    static let platforms = "settings.platforms"
}

enum PlatformSettings {
    static func load() -> Set<Platform> {
        let raw = UserDefaults.standard.stringArray(forKey: SettingsStoreKey.platforms) ?? []
        return Set(raw.compactMap { Platform(rawValue: $0) })
    }

    static func save(_ platforms: Set<Platform>) {
        UserDefaults.standard.set(platforms.map { $0.rawValue }, forKey: SettingsStoreKey.platforms)
    }
}
