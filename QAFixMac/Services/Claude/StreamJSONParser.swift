import Foundation

struct StreamJSONParser {
    static func parseLine(_ line: String) -> ClaudeStreamEvent {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return .unknown(rawJSON: line)
        }
        switch type {
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {
                var accumulated = ""
                for block in blocks {
                    guard let blockType = block["type"] as? String else { continue }
                    switch blockType {
                    case "text":
                        if let text = block["text"] as? String { accumulated += text }
                    case "tool_use":
                        let name = block["name"] as? String ?? "?"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let inputString = (try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted]))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        return .toolUse(name: name, input: inputString)
                    default:
                        continue
                    }
                }
                if !accumulated.isEmpty {
                    return .assistantText(accumulated)
                }
            }
            return .unknown(rawJSON: line)
        case "user":
            if let message = json["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let contents = block["content"] as? [[String: Any]] {
                        let text = contents.compactMap { $0["text"] as? String }.joined(separator: "\n")
                        return .toolResult(text)
                    }
                    if let text = block["content"] as? String {
                        return .toolResult(text)
                    }
                }
            }
            return .unknown(rawJSON: line)
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            return .system(subtype: subtype, raw: line)
        case "rate_limit_event":
            return .rateLimit(raw: line)
        case "result":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "error_during_execution" || subtype == "error_max_turns" {
                let message = (json["result"] as? String) ?? "Claude reported an error."
                return .error(message: message)
            }
            var usage = ClaudeUsage(
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                totalCostUSD: nil,
                durationMS: json["duration_ms"] as? Int
            )
            if let totalCost = json["total_cost_usd"] as? Double {
                usage.totalCostUSD = totalCost
            }
            if let usageDict = json["usage"] as? [String: Any] {
                usage.inputTokens = usageDict["input_tokens"] as? Int ?? 0
                usage.outputTokens = usageDict["output_tokens"] as? Int ?? 0
                usage.cacheCreationInputTokens = usageDict["cache_creation_input_tokens"] as? Int ?? 0
                usage.cacheReadInputTokens = usageDict["cache_read_input_tokens"] as? Int ?? 0
            }
            let text = json["result"] as? String
            return .result(usage: usage, text: text)
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["message"] as? String
                ?? "Claude reported an error."
            return .error(message: message)
        default:
            return .unknown(rawJSON: line)
        }
    }
}

final class NDJSONLineBuffer {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)
            if let text = String(data: lineData, encoding: .utf8), !text.isEmpty {
                lines.append(text)
            }
        }
        return lines
    }

    func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let tail = String(data: buffer, encoding: .utf8)
        buffer.removeAll()
        return tail?.isEmpty == false ? tail : nil
    }
}
