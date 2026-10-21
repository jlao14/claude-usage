import SwiftUI

/// A full-width menu-style row with an icon and a hover highlight.
struct MenuRow: View {
    let title: String
    let systemImage: String?
    var trailingSystemImage: String?
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                Spacer()
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.12 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { isHovering = $0 }
    }
}
