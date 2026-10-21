import Foundation
import Observation

/// Holds the latest snapshot per provider and refreshes them on a timer.
/// A failed refresh keeps the previous snapshot and records the error.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    private(set) var errors: [ProviderID: String] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    let settings: AppSettings
    @ObservationIgnored private let providers: [any UsageProvider]
    @ObservationIgnored private let alerts: AlertEngine
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Gauge shown next to the menu bar icon, per the Display setting.
    var headline: Gauge? {
        let title: String
        switch settings.menuBarMetric {
        case .session: title = "Session"
        case .weekly: title = "Weekly"
        case .iconOnly: return nil
        }
        return snapshots[.subscription]?.gauges.first { $0.title == title }
    }

    init(
        providers: [any UsageProvider] = UsageStore.defaultProviders(),
        settings: AppSettings = AppSettings(),
        notifier: any Notifier = NoopNotifier(),
        autostart: Bool = true
    ) {
        self.providers = providers
        self.settings = settings
        alerts = AlertEngine(settings: settings, notifier: notifier)
        if autostart { startPolling() }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            // Ends on its own once the store is gone.
            while !Task.isCancelled {
                guard await self?.refreshAll() != nil else { return }
                // Wait in short steps so a changed refresh interval applies quickly.
                var waited = 0
                while true {
                    guard let target = self?.settings.refreshSeconds else { return }
                    if waited >= target { break }
                    try? await Task.sleep(for: .seconds(5))
                    waited += 5
                }
            }
        }
    }

    static func defaultProviders() -> [any UsageProvider] {
        [SubscriptionProvider(), LocalLogsProvider()]
    }

    func refresh() {
        Task { await refreshAll() }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let results = await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, Error>).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.id, .success(try await provider.fetch(now: now))) }
                    catch { return (provider.id, .failure(error)) }
                }
            }
            var collected: [(ProviderID, Result<UsageSnapshot, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (id, result) in results {
            switch result {
            case .success(let snapshot):
                snapshots[id] = snapshot
                errors[id] = nil
            case .failure(let error):
                errors[id] = error.localizedDescription
            }
        }
        lastRefresh = now

        if let subscription = snapshots[.subscription], errors[.subscription] == nil {
            await alerts.evaluate(gauges: subscription.gauges, now: now)
        }
    }
}
