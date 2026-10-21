import Foundation
import Testing
@testable import ClaudeUsage

private let usageJSON = #"""
{
  "five_hour": {"utilization": 37.0, "resets_at": "2026-10-21T20:00:00.123456+00:00"},
  "seven_day": {"utilization": 12.5, "resets_at": "2026-10-27T09:00:00Z"},
  "seven_day_opus": null,
  "seven_day_oauth_apps": null,
  "extra_usage": {"is_enabled": false}
}
"""#

private final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (status, body) = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? (500, "") : responses.removeFirst()
        }
        return (Data(body.utf8), status)
    }
}

private final class StubCredentials: CredentialSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [OAuthCredentials]
    private(set) var loads = 0

    init(_ queue: [OAuthCredentials]) { self.queue = queue }

    func load() throws -> OAuthCredentials {
        lock.lock(); defer { lock.unlock() }
        loads += 1
        guard !queue.isEmpty else { throw ProviderError.notSignedIn }
        return queue.count > 1 ? queue.removeFirst() : queue[0]
    }
}

private func creds(_ token: String, expiresAt: Date? = nil) -> OAuthCredentials {
    OAuthCredentials(accessToken: token, expiresAt: expiresAt)
}

// MARK: Parsing

@Test func parsesClaudeCodeCredentialJSON() throws {
    let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1790000000000,"subscriptionType":"max"}}"#
    let parsed = try CredentialParser.parse(Data(json.utf8))
    #expect(parsed.accessToken == "tok")
    #expect(parsed.expiresAt == Date(timeIntervalSince1970: 1_790_000_000))
    #expect(parsed.subscriptionType == "max")
    #expect(throws: ProviderError.notSignedIn) { try CredentialParser.parse(Data("{}".utf8)) }
    #expect(throws: ProviderError.notSignedIn) { try CredentialParser.parse(Data("garbage".utf8)) }
}

@Test func parsesUsageWindowsAndSkipsNullOnes() throws {
    let gauges = try UsageResponseParser.gauges(from: Data(usageJSON.utf8))
    #expect(gauges.map(\.title) == ["Session", "Weekly"])
    #expect(gauges[0].percent == 37)
    #expect(gauges[1].percent == 12.5)
    #expect(gauges[0].resetsAt != nil)
    #expect(gauges[1].resetsAt == (try! Date("2026-10-27T09:00:00Z", strategy: .iso8601)))
}

@Test func unexpectedResponseListsFieldNames() {
    #expect(throws: ProviderError.unexpectedResponse(keys: ["bar", "foo"])) {
        try UsageResponseParser.gauges(from: Data(#"{"foo":1,"bar":2}"#.utf8))
    }
}

// MARK: Provider

@Test func fetchBuildsSnapshotAndSendsAuthHeaders() async throws {
    let http = StubHTTP([(200, usageJSON)])
    let provider = SubscriptionProvider(credentials: StubCredentials([OAuthCredentials(accessToken: "tok", subscriptionType: "max")]), http: http)
    let snapshot = try await provider.fetch(now: Date())
    #expect(snapshot.gauges.count == 2)
    #expect(snapshot.plan == "Max")
    let request = try #require(http.requests.first)
    #expect(request.url == SubscriptionProvider.endpoint)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
}

@Test func repeatedFetchesWithinMinIntervalReuseResult() async throws {
    let http = StubHTTP([(200, usageJSON), (200, usageJSON)])
    let credentials = StubCredentials([creds("tok")])
    let provider = SubscriptionProvider(credentials: credentials, http: http, minInterval: 30)
    let now = Date()
    _ = try await provider.fetch(now: now)
    _ = try await provider.fetch(now: now.addingTimeInterval(10))
    #expect(http.requests.count == 1)
    _ = try await provider.fetch(now: now.addingTimeInterval(31))
    #expect(http.requests.count == 2)
    #expect(credentials.loads == 1) // token is cached between polls
}

@Test func unauthorizedRereadsCredentialsOnceThenSucceeds() async throws {
    let http = StubHTTP([(401, "{}"), (200, usageJSON)])
    let credentials = StubCredentials([creds("old"), creds("new")])
    let provider = SubscriptionProvider(credentials: credentials, http: http)
    _ = try await provider.fetch(now: Date())
    #expect(http.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer new"])
}

@Test func persistentUnauthorizedMeansLoginExpired() async {
    let provider = SubscriptionProvider(credentials: StubCredentials([creds("tok")]), http: StubHTTP([(401, ""), (401, "")]))
    await #expect(throws: ProviderError.loginExpired) { try await provider.fetch(now: Date()) }
}

@Test func expiredTokenFailsWithoutCallingTheServer() async {
    let now = Date()
    let http = StubHTTP([(200, usageJSON)])
    let provider = SubscriptionProvider(credentials: StubCredentials([creds("tok", expiresAt: now.addingTimeInterval(-60))]), http: http)
    await #expect(throws: ProviderError.loginExpired) { try await provider.fetch(now: now) }
    #expect(http.requests.isEmpty)
}

@Test func mapsRateLimitAndServerErrors() async {
    let limited = SubscriptionProvider(credentials: StubCredentials([creds("t")]), http: StubHTTP([(429, "")]))
    await #expect(throws: ProviderError.rateLimited) { try await limited.fetch(now: Date()) }
    let broken = SubscriptionProvider(credentials: StubCredentials([creds("t")]), http: StubHTTP([(503, "")]))
    await #expect(throws: ProviderError.http(503)) { try await broken.fetch(now: Date()) }
}

// MARK: Real account (opt-in; macOS will ask to approve Keychain access)
// CLAUDE_USAGE_REAL_SUBSCRIPTION=1 swift test --filter realSubscriptionDump

@Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_USAGE_REAL_SUBSCRIPTION"] != nil))
func realSubscriptionDump() async throws {
    let snapshot = try await SubscriptionProvider().fetch(now: Date())
    for g in snapshot.gauges { print("REAL \(g.title): \(g.percent)% resets \(String(describing: g.resetsAt))") }
}
