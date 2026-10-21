import Foundation

/// A single progress-style reading, e.g. "5-hour session" at 42%.
struct Gauge: Identifiable, Sendable, Equatable {
    var id: String { title }
    var title: String
    /// 0...100
    var percent: Double
    var resetsAt: Date?
}

/// A labelled number, e.g. "Today" -> "$3.12".
struct Metric: Identifiable, Sendable, Equatable {
    var id: String { title }
    var title: String
    var value: String
}

/// One calendar day of usage, for the history chart.
struct DailyPoint: Identifiable, Sendable, Equatable {
    var id: Date { date }
    /// Start of the local calendar day.
    var date: Date
    var tokens: Int
    var costUSD: Double
    var hasUnpricedModels = false
}

/// Everything one provider reports in a single refresh.
struct UsageSnapshot: Sendable, Equatable {
    var gauges: [Gauge]
    var metrics: [Metric]
    var fetchedAt: Date
    /// Oldest to newest, one point per day.
    var series: [DailyPoint] = []
    /// Subscription tier, e.g. "Max".
    var plan: String?
    /// True while a provider is still a placeholder showing made-up numbers.
    var isSample = false
}

enum ProviderID: String, Sendable, CaseIterable {
    case subscription, localLogs

    var displayName: String {
        switch self {
        case .subscription: "Subscription limits"
        case .localLogs: "Claude Code (local)"
        }
    }
}
