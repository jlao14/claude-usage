import SwiftUI

struct MenuBarLabel: View {
    let gauge: Gauge?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            if let gauge {
                Text("\(Int(gauge.percent.rounded()))%")
                    .monospacedDigit()
            }
        }
    }
}
