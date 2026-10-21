import Foundation

/// One billed API response taken from a Claude Code session log.
struct UsageEntry: Sendable, Equatable {
    /// `message.id` + `requestId`; the log repeats a response once per content block.
    var key: String
    var timestamp: Date
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheWrite5mTokens: Int
    var cacheWrite1hTokens: Int
    var cacheReadTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens
    }
}

enum LogParser {
    private struct Line: Decodable {
        var type: String?
        var timestamp: String?
        var requestId: String?
        var message: Message?

        struct Message: Decodable {
            var id: String?
            var model: String?
            var usage: Usage?
        }

        struct Usage: Decodable {
            var input_tokens: Int?
            var output_tokens: Int?
            var cache_creation_input_tokens: Int?
            var cache_read_input_tokens: Int?
            var cache_creation: CacheCreation?
        }

        struct CacheCreation: Decodable {
            var ephemeral_5m_input_tokens: Int?
            var ephemeral_1h_input_tokens: Int?
        }
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let fractionalDate = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainDate = Date.ISO8601FormatStyle()

    /// Returns nil for any line that isn't an assistant message with usage.
    static func parse(line: Data) -> UsageEntry? {
        // Cheap prefilter: most lines (tool results, snapshots) never mention usage.
        guard line.range(of: usageMarker) != nil,
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "assistant",
              let message = decoded.message,
              let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let stamp = decoded.timestamp, let date = parseDate(stamp)
        else { return nil }

        let totalWrite = usage.cache_creation_input_tokens ?? 0
        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        // Without a TTL breakdown, treat all writes as the default 5-minute cache.
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? max(totalWrite - write1h, 0)

        var key = "\(message.id ?? "")|\(decoded.requestId ?? "")"
        if message.id == nil && decoded.requestId == nil { key += stamp }

        return UsageEntry(
            key: key,
            timestamp: date,
            model: model,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: fractionalDate)) ?? (try? Date(string, strategy: plainDate))
    }
}
