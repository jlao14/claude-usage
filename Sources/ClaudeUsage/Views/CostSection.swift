import SwiftUI

struct CostSection: View {
    let metrics: [Metric]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cost")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 2)
            ForEach(metrics) { metric in
                Text("\(metric.title): \(metric.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
