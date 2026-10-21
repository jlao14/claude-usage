import SwiftUI

enum Theme {
    static let accent = Color(red: 0.80, green: 0.49, blue: 0.37)
    static let warning = Color(red: 0.93, green: 0.69, blue: 0.25)
    static let track = Color.primary.opacity(0.12)

    /// Bars stay the accent colour until a limit is close.
    static func tint(forPercent percent: Double) -> Color {
        switch percent {
        case 90...: .red
        case 75...: warning
        default: accent
        }
    }
}
