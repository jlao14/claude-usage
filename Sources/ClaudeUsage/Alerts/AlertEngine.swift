import Foundation

/// Decides when a usage gauge has crossed 50 / 75 / 90% and sends one alert per crossing.
///
/// State is remembered per limit window (keyed by its reset time) and saved, so
/// relaunching the app never repeats an alert, and a window reset re-arms every level.
@MainActor
final class AlertEngine {
    struct State: Codable, Equatable {
        var window: String
        var fired: Set<Int>
    }

    private static let storageKey = "alertState"

    private let settings: AppSettings
    private let notifier: any Notifier
    private var states: [String: State]

    init(settings: AppSettings, notifier: any Notifier) {
        self.settings = settings
        self.notifier = notifier
        states = settings.defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: State].self, from: $0) } ?? [:]
    }

    func evaluate(gauges: [Gauge], now: Date) async {
        for gauge in gauges {
            guard let enabledForGauge = isAlertable(gauge.title) else { continue }

            let window = gauge.resetsAt.map { String(Int(($0.timeIntervalSince1970 / 60).rounded())) } ?? "none"
            var fired = states[gauge.title].flatMap { $0.window == window ? $0.fired : nil } ?? []
            // Usage dropped below a level (e.g. a correction): re-arm it.
            fired = fired.filter { Double($0) <= gauge.percent }

            // Track every level even while alerts are off, so turning them on later
            // doesn't instantly announce a level that was crossed long ago.
            let crossed = AppSettings.thresholdChoices.filter { Double($0) <= gauge.percent && !fired.contains($0) }
            states[gauge.title] = State(window: window, fired: fired.union(crossed))

            guard settings.alertsEnabled, enabledForGauge,
                  let level = crossed.filter(settings.thresholds.contains).max()
            else { continue }

            let percent = Int(gauge.percent.rounded())
            var body = "\(percent)% of your \(gauge.title.lowercased()) limit is used."
            if let resetsAt = gauge.resetsAt, resetsAt > now {
                body += " Resets in \(Format.countdown(from: now, to: resetsAt))."
            }
            await notifier.send(
                title: "Claude \(gauge.title.lowercased()) usage at \(percent)%",
                body: body,
                playSound: level >= 90
            )
        }
        persist()
    }

    /// nil for gauges that never alert (Opus, Sonnet); otherwise the user's per-gauge toggle.
    private func isAlertable(_ title: String) -> Bool? {
        switch title {
        case "Session": settings.alertSession
        case "Weekly": settings.alertWeekly
        default: nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(states) {
            settings.defaults.set(data, forKey: Self.storageKey)
        }
    }
}
