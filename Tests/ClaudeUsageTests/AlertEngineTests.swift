import Foundation
import Testing
@testable import ClaudeUsage

private final class FakeNotifier: Notifier, @unchecked Sendable {
    struct Sent: Equatable { var title: String; var body: String; var sound: Bool }
    private let lock = NSLock()
    private var items: [Sent] = []
    var sent: [Sent] { lock.withLock { items } }

    func send(title: String, body: String, playSound: Bool) async {
        lock.withLock { items.append(Sent(title: title, body: body, sound: playSound)) }
    }
}

private let now = Date(timeIntervalSince1970: 1_790_000_000)
private func gauge(_ title: String, _ percent: Double, resetsIn: TimeInterval = 5000) -> Gauge {
    Gauge(title: title, percent: percent, resetsAt: now.addingTimeInterval(resetsIn))
}
private func gauge(_ percent: Double, resetsIn: TimeInterval = 5000) -> Gauge {
    gauge("Session", percent, resetsIn: resetsIn)
}

@MainActor
private func makeEngine(_ settings: AppSettings = .ephemeral()) -> (AlertEngine, FakeNotifier, AppSettings) {
    let notifier = FakeNotifier()
    return (AlertEngine(settings: settings, notifier: notifier), notifier, settings)
}

@MainActor @Test func silentBelowFirstThreshold() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(49.9)], now: now)
    #expect(notifier.sent.isEmpty)
}

@MainActor @Test func firesOnceWhenCrossingAndNotAgainAtSameLevel() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(50)], now: now)
    await engine.evaluate(gauges: [gauge(55)], now: now)
    await engine.evaluate(gauges: [gauge(74)], now: now)
    #expect(notifier.sent.count == 1)
    #expect(notifier.sent[0].title == "Claude session usage at 50%")
    #expect(notifier.sent[0].sound == false)
}

@MainActor @Test func eachHigherLevelFiresInTurn() async {
    let (engine, notifier, _) = makeEngine()
    for p in [51.0, 76, 91] { await engine.evaluate(gauges: [gauge(p)], now: now) }
    #expect(notifier.sent.map(\.title) == [
        "Claude session usage at 51%", "Claude session usage at 76%", "Claude session usage at 91%",
    ])
    #expect(notifier.sent.map(\.sound) == [false, false, true]) // sound only for 90%+
}

@MainActor @Test func jumpingPastSeveralLevelsSendsOneAlert() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(40)], now: now)
    await engine.evaluate(gauges: [gauge(80)], now: now)
    #expect(notifier.sent.count == 1)
    #expect(notifier.sent[0].title == "Claude session usage at 80%")
    // 50 and 75 were both consumed by that jump.
    await engine.evaluate(gauges: [gauge(85)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func windowResetRearmsEveryLevel() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(60, resetsIn: 1000)], now: now)
    await engine.evaluate(gauges: [gauge(5, resetsIn: 1000 + 5 * 3600)], now: now) // new window
    await engine.evaluate(gauges: [gauge(55, resetsIn: 1000 + 5 * 3600)], now: now)
    #expect(notifier.sent.count == 2)
}

@MainActor @Test func tinyResetTimeDriftDoesNotRearm() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(60, resetsIn: 1000.2)], now: now)
    await engine.evaluate(gauges: [gauge(61, resetsIn: 1000.7)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func weeklyIsTrackedIndependentlyFromSession() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge("Session", 55), gauge("Weekly", 76)], now: now)
    #expect(notifier.sent.map(\.title) == ["Claude session usage at 55%", "Claude weekly usage at 76%"])
}

@MainActor @Test func opusAndSonnetGaugesNeverAlert() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge("Opus", 99), gauge("Sonnet", 99)], now: now)
    #expect(notifier.sent.isEmpty)
}

@MainActor @Test func perGaugeAndMasterTogglesAreRespected() async {
    let settings = AppSettings.ephemeral()
    settings.alertSession = false
    let (engine, notifier, _) = makeEngine(settings)
    await engine.evaluate(gauges: [gauge("Session", 80), gauge("Weekly", 80)], now: now)
    #expect(notifier.sent.map(\.title) == ["Claude weekly usage at 80%"])

    settings.alertsEnabled = false
    await engine.evaluate(gauges: [gauge("Weekly", 95)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func levelsCrossedWhileDisabledAreNotAnnouncedLater() async {
    let settings = AppSettings.ephemeral()
    settings.alertsEnabled = false
    let (engine, notifier, _) = makeEngine(settings)
    await engine.evaluate(gauges: [gauge(80)], now: now)
    settings.alertsEnabled = true
    await engine.evaluate(gauges: [gauge(82)], now: now)
    #expect(notifier.sent.isEmpty)
    await engine.evaluate(gauges: [gauge(91)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func onlySelectedThresholdsAlert() async {
    let settings = AppSettings.ephemeral()
    settings.thresholds = [90]
    let (engine, notifier, _) = makeEngine(settings)
    await engine.evaluate(gauges: [gauge(80)], now: now)
    #expect(notifier.sent.isEmpty)
    await engine.evaluate(gauges: [gauge(91)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func stateSurvivesRelaunch() async {
    let settings = AppSettings.ephemeral()
    let (first, notifier, _) = makeEngine(settings)
    await first.evaluate(gauges: [gauge(80)], now: now)
    #expect(notifier.sent.count == 1)

    let relaunched = AlertEngine(settings: settings, notifier: notifier)
    await relaunched.evaluate(gauges: [gauge(81)], now: now)
    #expect(notifier.sent.count == 1)
}

@MainActor @Test func bodyMentionsResetTime() async {
    let (engine, notifier, _) = makeEngine()
    await engine.evaluate(gauges: [gauge(80, resetsIn: 83 * 60)], now: now)
    #expect(notifier.sent[0].body == "80% of your session limit is used. Resets in 1h 23m.")
}

// MARK: Settings

@MainActor @Test func settingsDefaultsAndPersistence() {
    let defaults = UserDefaults(suiteName: "claude-usage-\(UUID().uuidString)")!
    let fresh = AppSettings(defaults: defaults)
    #expect(fresh.refreshSeconds == 60)
    #expect(fresh.menuBarMetric == .session)
    #expect(fresh.alertsEnabled && fresh.alertSession && fresh.alertWeekly)
    #expect(fresh.thresholds == [50, 75, 90])

    fresh.refreshSeconds = 300
    fresh.menuBarMetric = .weekly
    fresh.alertWeekly = false
    fresh.thresholds = [75]

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.refreshSeconds == 300)
    #expect(reloaded.menuBarMetric == .weekly)
    #expect(reloaded.alertWeekly == false)
    #expect(reloaded.thresholds == [75])
}

@MainActor @Test func settingsIgnoreInvalidStoredValues() {
    let defaults = UserDefaults(suiteName: "claude-usage-\(UUID().uuidString)")!
    defaults.set(7, forKey: "refreshSeconds")
    defaults.set("bogus", forKey: "menuBarMetric")
    defaults.set([10, 75, 99], forKey: "alertThresholds")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.refreshSeconds == 60)
    #expect(settings.menuBarMetric == .session)
    #expect(settings.thresholds == [75])
}

@MainActor @Test func headlineFollowsMenuBarSetting() async {
    let settings = AppSettings.ephemeral()
    let sub = SampleProvider(id: .subscription, gauges: [
        Gauge(title: "Session", percent: 15, resetsAt: nil),
        Gauge(title: "Weekly", percent: 46, resetsAt: nil),
    ])
    let store = UsageStore(providers: [sub], settings: settings, autostart: false)
    await store.refreshAll()
    #expect(store.headline?.percent == 15)
    settings.menuBarMetric = .weekly
    #expect(store.headline?.percent == 46)
    settings.menuBarMetric = .iconOnly
    #expect(store.headline == nil)
}
