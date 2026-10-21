import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case session, weekly, iconOnly

        var id: String { rawValue }
        var label: String {
            switch self {
            case .session: "Session (5-hour) %"
            case .weekly: "Weekly %"
            case .iconOnly: "Icon only"
            }
        }
    }

    static let thresholdChoices = [50, 75, 90]
    static let refreshChoices = [30, 60, 120, 300]

    private enum Key {
        static let refresh = "refreshSeconds"
        static let menuBar = "menuBarMetric"
        static let alertsEnabled = "alertsEnabled"
        static let alertSession = "alertSession"
        static let alertWeekly = "alertWeekly"
        static let thresholds = "alertThresholds"
    }

    @ObservationIgnored let defaults: UserDefaults

    var refreshSeconds: Int { didSet { defaults.set(refreshSeconds, forKey: Key.refresh) } }
    var menuBarMetric: MenuBarMetric { didSet { defaults.set(menuBarMetric.rawValue, forKey: Key.menuBar) } }
    var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) } }
    var alertSession: Bool { didSet { defaults.set(alertSession, forKey: Key.alertSession) } }
    var alertWeekly: Bool { didSet { defaults.set(alertWeekly, forKey: Key.alertWeekly) } }
    var thresholds: Set<Int> { didSet { defaults.set(thresholds.sorted(), forKey: Key.thresholds) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let refresh = defaults.integer(forKey: Key.refresh)
        refreshSeconds = Self.refreshChoices.contains(refresh) ? refresh : 60
        menuBarMetric = defaults.string(forKey: Key.menuBar).flatMap(MenuBarMetric.init(rawValue:)) ?? .session
        alertsEnabled = defaults.object(forKey: Key.alertsEnabled) as? Bool ?? true
        alertSession = defaults.object(forKey: Key.alertSession) as? Bool ?? true
        alertWeekly = defaults.object(forKey: Key.alertWeekly) as? Bool ?? true
        let stored = (defaults.array(forKey: Key.thresholds) as? [Int]).map(Set.init)
        thresholds = stored?.intersection(Self.thresholdChoices) ?? Set(Self.thresholdChoices)
    }

    /// Settings backed by a throwaway defaults domain, for tests and previews.
    static func ephemeral() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "claude-usage-\(UUID().uuidString)")!)
    }
}
