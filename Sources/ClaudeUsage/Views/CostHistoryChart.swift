import Charts
import SwiftUI

/// 30 days of estimated cost as bars. Hovering a bar shows that day's cost and tokens.
struct CostHistoryChart: View {
    let series: [DailyPoint]
    @State private var hoveredDate: Date?

    private var shown: DailyPoint? {
        guard let hoveredDate else { return series.last }
        let day = Calendar.current.startOfDay(for: hoveredDate)
        return series.first { $0.date == day } ?? series.last
    }

    private var total: (cost: Double, unpriced: Bool) {
        (series.reduce(0) { $0 + $1.costUSD }, series.contains { $0.hasUnpricedModels })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(series) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Cost", point.costUSD)
                )
                .cornerRadius(1.5)
                .foregroundStyle(Theme.accent.opacity(hoveredDate == nil || shown?.id == point.id ? 1 : 0.4))
            }
            .chartXSelection(value: $hoveredDate)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
            .frame(height: 96)

            if let shown {
                Text("\(shown.date.formatted(.dateTime.month(.abbreviated).day())): \(Format.dollars(shown.costUSD, lowerBound: shown.hasUnpricedModels)) · \(Format.tokens(shown.tokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Total (\(series.count)d): \(Format.dollars(total.cost, lowerBound: total.unpriced))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }
}
