import Foundation

struct UsageTotals: Equatable {
    var tokens = 0
    var costUSD = 0.0
    /// True when some entries used a model with no known price, so `costUSD` is a lower bound.
    var hasUnpricedModels = false

    init(entries: [UsageEntry]) {
        for entry in entries {
            tokens += entry.totalTokens
            if let cost = Pricing.cost(of: entry) {
                costUSD += cost
            } else {
                hasUnpricedModels = true
            }
        }
    }
}

/// A rolling 5-hour usage window, the unit Claude subscription limits reset on.
struct UsageBlock: Equatable {
    var start: Date
    var end: Date
    var totals: UsageTotals
}

enum LogAggregator {
    static let blockLength: TimeInterval = 5 * 3600

    /// The block that contains `now`, or nil if the last block already ended.
    /// A block opens at the top of the hour of its first message and lasts five
    /// hours; a message after that (or after a 5h gap) opens the next block.
    static func activeBlock(entries: [UsageEntry], now: Date) -> UsageBlock? {
        var start: Date?
        var last: Date?
        var members: [UsageEntry] = []

        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) where entry.timestamp <= now {
            if let s = start, let l = last,
               entry.timestamp < s.addingTimeInterval(blockLength),
               entry.timestamp.timeIntervalSince(l) < blockLength {
                members.append(entry)
            } else {
                start = floorToHour(entry.timestamp)
                members = [entry]
            }
            last = entry.timestamp
        }

        guard let start, now < start.addingTimeInterval(blockLength) else { return nil }
        return UsageBlock(start: start, end: start.addingTimeInterval(blockLength), totals: UsageTotals(entries: members))
    }

    /// One point per local calendar day ending today, oldest first; days with no usage are zero.
    static func dailySeries(entries: [UsageEntry], now: Date, days: Int, calendar: Calendar = .current) -> [DailyPoint] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: [UsageEntry]] = [:]
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.timestamp), default: []].append(entry)
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let totals = UsageTotals(entries: buckets[day] ?? [])
            return DailyPoint(date: day, tokens: totals.tokens, costUSD: totals.costUSD, hasUnpricedModels: totals.hasUnpricedModels)
        }
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}

enum Format {
    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000: "\(n)"
        case ..<1_000_000: String(format: "%.1fK", Double(n) / 1_000)
        case ..<1_000_000_000: String(format: "%.1fM", Double(n) / 1_000_000)
        default: String(format: "%.1fB", Double(n) / 1_000_000_000)
        }
    }

    /// `lowerBound` appends "+" when some usage couldn't be priced.
    static func dollars(_ value: Double, lowerBound: Bool = false) -> String {
        String(format: "$%.2f", value) + (lowerBound ? "+" : "")
    }

    static func cost(_ totals: UsageTotals) -> String {
        dollars(totals.costUSD, lowerBound: totals.hasUnpricedModels)
    }

    /// "$38.00 · 14M tokens"
    static func summary(_ totals: UsageTotals) -> String {
        "\(cost(totals)) · \(tokens(totals.tokens)) tokens"
    }

    /// "1h 23m", "2d 1h", "<1m"
    static func countdown(from now: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }

    /// "max" -> "Max", "max_20x" -> "Max 20x"
    static func plan(_ raw: String) -> String {
        let words = raw.split(separator: "_").map(String.init)
        guard let first = words.first else { return raw }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}
