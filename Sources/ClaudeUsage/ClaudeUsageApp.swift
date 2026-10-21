import SwiftUI

@main
struct ClaudeUsageApp: App {
    @State private var settings: AppSettings
    @State private var store: UsageStore

    init() {
        // Menu bar only: no Dock icon (equivalent to LSUIElement).
        NSApplication.shared.setActivationPolicy(.accessory)

        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: UsageStore(settings: settings, notifier: SystemNotifier.shared))

        SystemNotifier.shared.activate()
        if settings.alertsEnabled {
            Task { await SystemNotifier.shared.requestAuthorizationIfNeeded() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(gauge: store.headline)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
