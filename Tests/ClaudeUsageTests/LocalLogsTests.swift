import Foundation
import Testing
@testable import ClaudeUsage

private func line(
    id: String, request: String = "req_1", model: String = "claude-opus-5-5",
    at timestamp: String, input: Int = 2, output: Int = 10, write: Int = 0, read: Int = 0,
    write1h: Int? = nil, type: String = "assistant"
) -> String {
    var creation = ""
    if let write1h {
        creation = #","cache_creation":{"ephemeral_5m_input_tokens":\#(write - write1h),"ephemeral_1h_input_tokens":\#(write1h)}"#
    }
    return #"{"type":"\#(type)","timestamp":"\#(timestamp)","requestId":"\#(request)","message":{"id":"\#(id)","model":"\#(model)","content":[],"usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read)\#(creation)}}}"#
}

private func date(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

// MARK: Parser

@Test func parsesAssistantLine() throws {
    let raw = line(id: "msg_1", at: "2026-10-21T13:34:12.345Z", input: 2, output: 989, write: 17019, read: 24264)
    let entry = try #require(LogParser.parse(line: Data(raw.utf8)))
    #expect(entry.key == "msg_1|req_1")
    #expect(entry.model == "claude-opus-5-5")
    #expect(entry.inputTokens == 2)
    #expect(entry.outputTokens == 989)
    #expect(entry.cacheWrite5mTokens == 17019)
    #expect(entry.cacheReadTokens == 24264)
    #expect(entry.totalTokens == 2 + 989 + 17019 + 24264)
}

@Test func splitsCacheWritesByTTLWhenPresent() throws {
    let raw = line(id: "msg_1", at: "2026-10-21T13:34:12Z", write: 1000, write1h: 400)
    let entry = try #require(LogParser.parse(line: Data(raw.utf8)))
    #expect(entry.cacheWrite5mTokens == 600)
    #expect(entry.cacheWrite1hTokens == 400)
}

@Test func ignoresLinesWithoutUsage() {
    let user = line(id: "msg_1", at: "2026-10-21T13:34:12Z", type: "user")
    #expect(LogParser.parse(line: Data(user.utf8)) == nil)
    #expect(LogParser.parse(line: Data(#"{"type":"assistant","message":{"id":"x"}}"#.utf8)) == nil)
    #expect(LogParser.parse(line: Data("not json at all \"usage\"".utf8)) == nil)
    let synthetic = line(id: "msg_2", model: "<synthetic>", at: "2026-10-21T13:34:12Z")
    #expect(LogParser.parse(line: Data(synthetic.utf8)) == nil)
}

// MARK: Pricing

private func entry(_ model: String = "claude-opus-5-5", input: Int = 0, output: Int = 0, read: Int = 0, w5: Int = 0, w1: Int = 0) -> UsageEntry {
    UsageEntry(key: "k", timestamp: Date(), model: model, inputTokens: input, outputTokens: output,
               cacheWrite5mTokens: w5, cacheWrite1hTokens: w1, cacheReadTokens: read)
}

@Test func opus55CostMatchesPriceTable() throws {
    // $4 in / $20 out / $0.20 cache read / 1.25x and 2x of input for writes, per million tokens.
    #expect(try #require(Pricing.cost(of: entry(input: 1_000_000))) == 4.0)
    #expect(try #require(Pricing.cost(of: entry(output: 1_000_000))) == 20.0)
    #expect(try #require(Pricing.cost(of: entry(read: 1_000_000))) == 0.20)
    #expect(try #require(Pricing.cost(of: entry(w5: 1_000_000))) == 5.0)
    #expect(try #require(Pricing.cost(of: entry(w1: 1_000_000))) == 8.0)
}

@Test func modelLookupHandlesSnapshotDatesAndUnknowns() {
    #expect(Pricing.price(for: "claude-opus-5-5-20260401") == Pricing.table["claude-opus-5-5"])
    #expect(Pricing.price(for: "claude-sonnet-5-5") == Pricing.table["claude-sonnet-5-5"])
    #expect(Pricing.price(for: "claude-opus-5-1") == nil) // not a date suffix, so not Opus 5
    #expect(Pricing.price(for: "gpt-4") == nil)
    #expect(Pricing.cost(of: entry("some-future-model", input: 5)) == nil)
}

@Test func unpricedModelsMarkTotalsAsLowerBound() {
    let totals = UsageTotals(entries: [entry(input: 1_000_000), entry("mystery", input: 500)])
    #expect(totals.hasUnpricedModels)
    #expect(totals.tokens == 1_000_500)
    #expect(Format.cost(totals) == "$4.00+")
}

// MARK: Blocks

private func at(_ time: String) -> UsageEntry {
    var e = entry(input: 100)
    e.timestamp = date("2026-10-21T\(time):00Z")
    return e
}

@Test func activeBlockStartsAtTopOfHourAndLastsFiveHours() throws {
    let entries = [at("10:20"), at("11:00")]
    let block = try #require(LogAggregator.activeBlock(entries: entries, now: date("2026-10-21T12:00:00Z")))
    #expect(block.start == date("2026-10-21T10:00:00Z"))
    #expect(block.end == date("2026-10-21T15:00:00Z"))
    #expect(block.totals.tokens == 200)
}

@Test func blockIsNilOnceItHasEnded() {
    #expect(LogAggregator.activeBlock(entries: [at("10:20")], now: date("2026-10-21T15:00:00Z")) == nil)
}

@Test func messageAfterBlockEndOpensNewBlock() throws {
    let entries = [at("01:10"), at("02:00"), at("07:30")]
    let block = try #require(LogAggregator.activeBlock(entries: entries, now: date("2026-10-21T08:00:00Z")))
    #expect(block.start == date("2026-10-21T07:00:00Z"))
    #expect(block.totals.tokens == 100)
}

@Test func formatsTokenCounts() {
    #expect(Format.tokens(834) == "834")
    #expect(Format.tokens(34_500) == "34.5K")
    #expect(Format.tokens(1_200_000) == "1.2M")
}

// MARK: Provider

private func tempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "claude-usage-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appending(path: "proj"), withIntermediateDirectories: true)
    return url
}

private func append(_ text: String, to file: URL) throws {
    if let handle = try? FileHandle(forWritingTo: file) {
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    } else {
        try Data(text.utf8).write(to: file)
    }
}

@Test func providerDedupesRepeatedMessagesAndReadsIncrementally() async throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "proj/session.jsonl")
    let now = Date()
    let stamp = now.addingTimeInterval(-60).formatted(.iso8601)

    // The same response logged three times (one line per content block) counts once.
    let dup = line(id: "msg_A", at: stamp, input: 100, output: 0)
    try append([dup, dup, dup, line(id: "msg_B", at: stamp, input: 50, output: 0)].joined(separator: "\n") + "\n", to: file)

    let provider = LocalLogsProvider(roots: [root])
    let first = try await provider.fetch(now: now)
    #expect(await provider.entryCount == 2)
    #expect(first.metrics.first { $0.title == "Today" }?.value.hasSuffix("· 150 tokens") == true)
    #expect(first.series.count == 30)
    #expect(first.series.last?.tokens == 150)

    // A half-written trailing line is ignored until its newline arrives.
    let partial = line(id: "msg_C", at: stamp, input: 7, output: 0)
    try append(String(partial.prefix(40)), to: file)
    _ = try await provider.fetch(now: now)
    #expect(await provider.entryCount == 2)

    try append(String(partial.dropFirst(40)) + "\n", to: file)
    let third = try await provider.fetch(now: now)
    #expect(await provider.entryCount == 3)
    #expect(third.metrics.first { $0.title == "Today" }?.value.hasSuffix("· 157 tokens") == true)
    #expect(third.metrics.first { $0.title == "Last 30 days" }?.value.hasSuffix("· 157 tokens") == true)
}

@Test func providerThrowsWhenNoLogDirectoryExists() async {
    let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString)")
    let provider = LocalLogsProvider(roots: [missing])
    await #expect(throws: ProviderError.self) { try await provider.fetch(now: Date()) }
}

@Test func providerExcludesEntriesOutsideLookback() async throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let old = now.addingTimeInterval(-20 * 86400).formatted(.iso8601)
    try append(line(id: "msg_old", at: old) + "\n", to: root.appending(path: "proj/old.jsonl"))
    let provider = LocalLogsProvider(roots: [root], lookback: 8 * 86400)
    _ = try await provider.fetch(now: now)
    #expect(await provider.entryCount == 0)
}

// MARK: Real data (opt-in): CLAUDE_USAGE_REAL_LOGS=1 swift test --filter realLogs

@Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_USAGE_REAL_LOGS"] != nil))
func realLogsDump() async throws {
    let provider = LocalLogsProvider()
    let snapshot = try await provider.fetch(now: Date())
    print("REAL entries:", await provider.entryCount)
    for m in snapshot.metrics { print("REAL \(m.title): \(m.value)") }
}

// MARK: Daily series and formatting

@Test func dailySeriesIsZeroFilledOldestFirst() throws {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = date("2026-10-21T15:00:00Z")
    var a = entry(input: 100); a.timestamp = date("2026-10-21T01:00:00Z")
    var b = entry(input: 50); b.timestamp = date("2026-10-19T23:59:00Z")
    var c = entry(input: 25); c.timestamp = date("2026-10-19T00:00:00Z")
    let series = LogAggregator.dailySeries(entries: [a, b, c], now: now, days: 4, calendar: utc)
    #expect(series.map(\.date) == ["2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21"].map { date("\($0)T00:00:00Z") })
    #expect(series.map(\.tokens) == [0, 75, 0, 100])
}

@Test func formatsCountdowns() {
    let now = date("2026-10-21T12:00:00Z")
    #expect(Format.countdown(from: now, to: now.addingTimeInterval(30)) == "<1m")
    #expect(Format.countdown(from: now, to: now.addingTimeInterval(23 * 60)) == "23m")
    #expect(Format.countdown(from: now, to: now.addingTimeInterval(83 * 60)) == "1h 23m")
    #expect(Format.countdown(from: now, to: now.addingTimeInterval(49 * 3600)) == "2d 1h")
    #expect(Format.countdown(from: now, to: now.addingTimeInterval(-5)) == "now")
}

@Test func formatsPlanNames() {
    #expect(Format.plan("max") == "Max")
    #expect(Format.plan("pro") == "Pro")
    #expect(Format.plan("max_20x") == "Max 20x")
}
