import Foundation

protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

struct URLSessionHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

enum UsageResponseParser {
    private static let windows: [(key: String, title: String)] = [
        ("five_hour", "Session"),
        ("seven_day", "Weekly"),
        ("seven_day_opus", "Opus"),
        ("seven_day_sonnet", "Sonnet"),
    ]

    private static let fractionalDate = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainDate = Date.ISO8601FormatStyle()

    /// Reads whichever known windows are present; unknown or null windows are skipped.
    /// `utilization` is taken to be a percentage (0-100).
    static func gauges(from data: Data) throws -> [Gauge] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.unexpectedResponse(keys: [])
        }
        let gauges = windows.compactMap { key, title -> Gauge? in
            guard let window = root[key] as? [String: Any],
                  let utilization = (window["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            let resets = (window["resets_at"] as? String).flatMap(parseDate)
            return Gauge(title: title, percent: utilization, resetsAt: resets)
        }
        guard !gauges.isEmpty else { throw ProviderError.unexpectedResponse(keys: root.keys.sorted()) }
        return gauges
    }

    private static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: fractionalDate)) ?? (try? Date(string, strategy: plainDate))
    }
}

/// Pro/Max plan limits: the same numbers Claude Code's `/usage` shows.
///
/// This uses the OAuth token Claude Code stored and an undocumented endpoint, so
/// Anthropic can change it at any time. Failures surface as a card warning and
/// never affect the other providers.
actor SubscriptionProvider: UsageProvider {
    nonisolated let id = ProviderID.subscription

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let credentials: any CredentialSource
    private let http: any HTTPClient
    private let minInterval: TimeInterval
    private var cachedCredentials: OAuthCredentials?
    private var lastSnapshot: UsageSnapshot?

    /// - Parameter minInterval: repeated refreshes inside this window reuse the last result,
    ///   so the Refresh button can't hammer the endpoint.
    init(
        credentials: any CredentialSource = ClaudeCodeCredentialSource(),
        http: any HTTPClient = URLSessionHTTPClient(),
        minInterval: TimeInterval = 30
    ) {
        self.credentials = credentials
        self.http = http
        self.minInterval = minInterval
    }

    func fetch(now: Date) async throws -> UsageSnapshot {
        if let last = lastSnapshot, now.timeIntervalSince(last.fetchedAt) < minInterval {
            return last
        }

        var login = try currentCredentials(at: now)
        var response = try await request(token: login.accessToken)
        if response.status == 401 {
            // Claude Code may have refreshed the token since we cached it; re-read once.
            cachedCredentials = nil
            login = try currentCredentials(at: now)
            response = try await request(token: login.accessToken)
        }

        switch response.status {
        case 200..<300: break
        case 401: throw ProviderError.loginExpired
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.http(response.status)
        }

        let snapshot = UsageSnapshot(
            gauges: try UsageResponseParser.gauges(from: response.data),
            metrics: [],
            fetchedAt: now,
            plan: login.subscriptionType.map(Format.plan)
        )
        lastSnapshot = snapshot
        return snapshot
    }

    private func currentCredentials(at now: Date) throws -> OAuthCredentials {
        if let cached = cachedCredentials, !cached.isExpired(at: now) { return cached }
        let fresh = try credentials.load()
        guard !fresh.isExpired(at: now) else { throw ProviderError.loginExpired }
        cachedCredentials = fresh
        return fresh
    }

    private func request(token: String) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await http.send(request)
    }
}
