import Foundation
import Testing
@testable import ClaudeUsage

@MainActor
@Test func storeCollectsSnapshotsFromProviders() async {
    let store = UsageStore(
        providers: [SampleProvider.subscription(), SampleProvider(id: .localLogs, metrics: [Metric(title: "Tokens today", value: "1")])],
        settings: .ephemeral(),
        autostart: false
    )
    await store.refreshAll()
    #expect(store.headline?.percent == 42)
    #expect(store.snapshots.count == 2)
    #expect(store.errors.isEmpty)
}

@MainActor
@Test func failingProviderKeepsLastSnapshotAndReportsError() async {
    struct Flaky: UsageProvider {
        let id = ProviderID.localLogs
        func fetch(now: Date) async throws -> UsageSnapshot { throw ProviderError.noLogsFound }
    }
    let store = UsageStore(providers: [Flaky(), SampleProvider.subscription()], settings: .ephemeral(), autostart: false)
    await store.refreshAll()
    #expect(store.snapshots[.subscription] != nil)
    #expect(store.snapshots[.localLogs] == nil)
    #expect(store.errors[.localLogs] == ProviderError.noLogsFound.localizedDescription)
}
