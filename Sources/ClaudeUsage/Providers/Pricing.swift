import Foundation

struct ModelPrice: Sendable, Equatable {
    /// USD per million tokens.
    var input: Double
    var output: Double
    var cacheRead: Double

    // Cache writes cost a multiple of the input price: 1.25x for the 5-minute
    // cache, 2x for the 1-hour cache.
    static let cacheWrite5mMultiplier = 1.25
    static let cacheWrite1hMultiplier = 2.0
}

/// Per-model list prices used for the *estimated* cost of local usage.
/// Source: Anthropic model pricing as of 2026-10-06. Haiku 5.5 uses its
/// <=100K-prompt rate; the higher long-prompt tier is not modelled.
enum Pricing {
    static let table: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1.00),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.10),
    ]

    /// Matches a model id exactly, or with a trailing `-YYYYMMDD` snapshot date.
    static func price(for model: String) -> ModelPrice? {
        if let exact = table[model] { return exact }
        guard let dash = model.lastIndex(of: "-") else { return nil }
        let suffix = model[model.index(after: dash)...]
        guard suffix.count == 8, suffix.allSatisfy(\.isNumber) else { return nil }
        return table[String(model[..<dash])]
    }

    /// Estimated USD cost, or nil when the model has no known price.
    static func cost(of entry: UsageEntry) -> Double? {
        guard let p = price(for: entry.model) else { return nil }
        let input = Double(entry.inputTokens) * p.input
        let output = Double(entry.outputTokens) * p.output
        let read = Double(entry.cacheReadTokens) * p.cacheRead
        let write5m = Double(entry.cacheWrite5mTokens) * p.input * ModelPrice.cacheWrite5mMultiplier
        let write1h = Double(entry.cacheWrite1hTokens) * p.input * ModelPrice.cacheWrite1hMultiplier
        return (input + output + read + write5m + write1h) / 1_000_000
    }
}
