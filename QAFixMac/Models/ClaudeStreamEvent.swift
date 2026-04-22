import Foundation

struct ClaudeUsage: Equatable, Hashable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var totalCostUSD: Double?
    var durationMS: Int?
}

enum ClaudeStreamEvent: Equatable {
    case system(subtype: String, raw: String)
    case assistantText(String)
    case toolUse(name: String, input: String)
    case toolResult(String)
    case result(usage: ClaudeUsage, text: String?)
    case rateLimit(raw: String)
    case error(message: String)
    case unknown(rawJSON: String)

    static func == (lhs: ClaudeStreamEvent, rhs: ClaudeStreamEvent) -> Bool {
        switch (lhs, rhs) {
        case (.assistantText(let a), .assistantText(let b)): return a == b
        case (.toolUse(let n1, let i1), .toolUse(let n2, let i2)): return n1 == n2 && i1 == i2
        case (.toolResult(let a), .toolResult(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        case (.unknown(let a), .unknown(let b)): return a == b
        case (.rateLimit(let a), .rateLimit(let b)): return a == b
        case (.system(let st1, let r1), .system(let st2, let r2)): return st1 == st2 && r1 == r2
        case (.result(let u1, let t1), .result(let u2, let t2)): return u1 == u2 && t1 == t2
        default: return false
        }
    }
}
