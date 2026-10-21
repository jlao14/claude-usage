import SwiftUI

/// "Session" / "Weekly" block: title, thin progress bar, "15% used" and reset countdown.
struct UsageBarSection: View {
    let gauge: Gauge
    let now: Date

    private var fraction: Double { min(max(gauge.percent / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(gauge.title)
                .font(.system(size: 13, weight: .semibold))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(Theme.tint(forPercent: gauge.percent))
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                }
            }
            .frame(height: 7)
            HStack {
                Text("\(Int(gauge.percent.rounded()))% used")
                Spacer()
                if let resetsAt = gauge.resetsAt {
                    Text(resetsAt > now ? "Resets in \(Format.countdown(from: now, to: resetsAt))" : "Resets now")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

/// Inline warning shown when a source fails; the last good numbers stay visible above it.
struct ErrorNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}
