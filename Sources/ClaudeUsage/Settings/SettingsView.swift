import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettings(settings: settings)
                .tabItem { Label("Display", systemImage: "menubar.rectangle") }
            AlertSettings(settings: settings)
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 440, height: 380)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Refresh every", selection: $settings.refreshSeconds) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : seconds == 60 ? "1 minute" : "\(seconds / 60) minutes")
                            .tag(seconds)
                    }
                }
            } footer: {
                Text("Plan limits are requested from Claude at most every 30 seconds, however often you refresh.")
            }

            Section("About") {
                LabeledContent("Version", value: AppInfo.version)
                if let repository = AppInfo.repositoryURL {
                    Link("Source code and updates", destination: repository)
                }
                Text("Unofficial app. Not made, endorsed, or supported by Anthropic. \"Claude\" is a trademark of Anthropic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: $settings.menuBarMetric) {
                    ForEach(AppSettings.MenuBarMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
            } footer: {
                Text("The number next to the gauge icon. Colors and alerts are unaffected.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    @Bindable var settings: AppSettings
    @State private var permission: NotificationPermission?

    var body: some View {
        Form {
            Section {
                Toggle("Notify me when usage crosses a level", isOn: $settings.alertsEnabled)
            }

            Section("Limits") {
                Toggle("Session (5-hour)", isOn: $settings.alertSession)
                Toggle("Weekly", isOn: $settings.alertWeekly)
            }
            .disabled(!settings.alertsEnabled)

            Section("Levels") {
                ForEach(AppSettings.thresholdChoices, id: \.self) { level in
                    Toggle("\(level)% used", isOn: binding(for: level))
                }
            }
            .disabled(!settings.alertsEnabled)

            Section("Notifications") {
                permissionRow
                Button("Send Test Notification") {
                    Task {
                        await SystemNotifier.shared.requestAuthorizationIfNeeded()
                        await SystemNotifier.shared.send(
                            title: "Claude Usage",
                            body: "Test notification. Alerts are working.",
                            playSound: false
                        )
                        permission = await SystemNotifier.shared.permission()
                    }
                }
                .disabled(permission == .unavailable)
            }
        }
        .formStyle(.grouped)
        .task { permission = await SystemNotifier.shared.permission() }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case .allowed:
            Label("Allowed in System Settings", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Blocked in System Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Button("Open Notification Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
        case .notDetermined:
            Label("macOS will ask for permission the first time", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Notifications need the packaged app (not `swift run`)", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case nil:
            Text("Checking…").foregroundStyle(.secondary)
        }
    }

    private func binding(for level: Int) -> Binding<Bool> {
        Binding(
            get: { settings.thresholds.contains(level) },
            set: { isOn in
                if isOn { settings.thresholds.insert(level) } else { settings.thresholds.remove(level) }
            }
        )
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
    }

    /// Set at packaging time (REPO_URL), so forks point at their own repo.
    static var repositoryURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "ClaudeUsageRepositoryURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
}
