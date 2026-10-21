import SwiftUI

struct PopoverView: View {
    let store: UsageStore
    @AppStorage("costHistoryExpanded") private var historyExpanded = true
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Re-render every 30s so "Updated …" and the reset countdowns stay current.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 340)
    }

    private func content(now: Date) -> some View {
        let subscription = store.snapshots[.subscription]
        let local = store.snapshots[.localLogs]

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header(plan: subscription?.plan, now: now)
                Divider()

                if let subscription {
                    ForEach(subscription.gauges) { UsageBarSection(gauge: $0, now: now) }
                }
                if let error = store.errors[.subscription] { ErrorNote(message: error) }

                if let local {
                    Divider()
                    CostSection(metrics: local.metrics)
                }
                if let error = store.errors[.localLogs] { ErrorNote(message: error) }
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 2) {
                if let series = local?.series, !series.isEmpty {
                    Divider().padding(.horizontal, 8).padding(.bottom, 4)
                    MenuRow(
                        title: "Cost history (\(series.count) days)",
                        systemImage: nil,
                        trailingSystemImage: historyExpanded ? "chevron.down" : "chevron.right"
                    ) { withAnimation(.snappy(duration: 0.2)) { historyExpanded.toggle() } }
                    if historyExpanded {
                        CostHistoryChart(series: series)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                MenuRow(title: store.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise", isEnabled: !store.isRefreshing) {
                    store.refresh()
                }
                MenuRow(title: "Usage Dashboard", systemImage: "chart.bar") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                MenuRow(title: "Status Page", systemImage: "waveform.path.ecg") {
                    NSWorkspace.shared.open(URL(string: "https://status.claude.com")!)
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                MenuRow(title: "Settings…", systemImage: "gearshape") {
                    // A menu bar app isn't frontmost, so bring it forward or the window opens behind others.
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openSettings()
                }
                MenuRow(title: "Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func header(plan: String?, now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude").font(.system(size: 15, weight: .bold))
                Group {
                    if let last = store.lastRefresh {
                        Text("Updated \(last, format: .relative(presentation: .named))")
                    } else {
                        Text("Updating…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let plan {
                Text(plan).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
