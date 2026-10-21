import Foundation

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(now: Date) async throws -> UsageSnapshot
}

enum ProviderError: LocalizedError, Equatable {
    case noLogsFound
    case notSignedIn
    case keychainDenied
    case loginExpired
    case rateLimited
    case http(Int)
    case unexpectedResponse(keys: [String])

    var errorDescription: String? {
        switch self {
        case .noLogsFound: "No Claude Code logs found in ~/.claude/projects"
        case .notSignedIn: "Not signed in. Run `claude` and log in with your Claude account."
        case .keychainDenied: "Keychain access was denied for \"Claude Code-credentials\"."
        case .loginExpired: "Claude login expired. Run `claude` to sign in again."
        case .rateLimited: "Usage endpoint is rate limiting requests; will retry."
        case .http(let code): "Usage request failed (HTTP \(code))."
        case .unexpectedResponse(let keys):
            "Unexpected usage response (fields: \(keys.isEmpty ? "none" : keys.joined(separator: ", ")))."
        }
    }
}

/// Placeholder for providers that aren't built yet; reports fixed fake numbers.
struct SampleProvider: UsageProvider {
    let id: ProviderID
    var gauges: [Gauge] = []
    var metrics: [Metric] = []
    var series: [DailyPoint] = []
    var plan: String?

    func fetch(now: Date) async throws -> UsageSnapshot {
        UsageSnapshot(gauges: gauges, metrics: metrics, fetchedAt: now, series: series, plan: plan, isSample: true)
    }

    static func subscription(now: Date = Date()) -> SampleProvider {
        SampleProvider(id: .subscription, gauges: [
            Gauge(title: "Session", percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
            Gauge(title: "Weekly", percent: 68, resetsAt: now.addingTimeInterval(3 * 86400)),
        ])
    }
}
