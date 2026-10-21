import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ClaudeUsage

// CLAUDE_USAGE_RENDER=/path/to/out.png swift test --filter renderPopover
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_USAGE_RENDER"] != nil))
func renderPopover() async throws {
    let now = Date()
    let day = Calendar.current.startOfDay(for: now)
    let costs: [Double] = [8, 18, 12, 6, 70, 95, 40, 5, 3, 1, 0, 4, 2, 2, 0, 3, 2, 7, 3, 2, 3, 3, 2, 1, 0, 0, 9, 24, 38, 22]
    let series = costs.enumerated().map { i, cost in
        DailyPoint(date: Calendar.current.date(byAdding: .day, value: i - 29, to: day)!, tokens: Int(cost * 600_000), costUSD: cost)
    }
    let subscription = SampleProvider(
        id: .subscription,
        gauges: [
            Gauge(title: "Session", percent: 15, resetsAt: now.addingTimeInterval(83 * 60)),
            Gauge(title: "Weekly", percent: 46, resetsAt: now.addingTimeInterval(49 * 3600)),
            Gauge(title: "Sonnet", percent: 0, resetsAt: nil),
        ],
        plan: "Max"
    )
    let local = SampleProvider(id: .localLogs, metrics: [
        Metric(title: "Session", value: "$38.00 · 14M tokens"),
        Metric(title: "Today", value: "$93.59 · 58M tokens"),
        Metric(title: "Last 30 days", value: "$482.80 · 290M tokens"),
    ], series: series)

    let store = UsageStore(providers: [subscription, local], autostart: false)
    await store.refreshAll()

    let view = PopoverView(store: store)
        .background(Color(red: 0.10, green: 0.14, blue: 0.30))
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_USAGE_RENDER"]!))
}
