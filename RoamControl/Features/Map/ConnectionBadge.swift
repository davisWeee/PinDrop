import SwiftUI

struct ConnectionBadge: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption.weight(.semibold))

            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection status: \(label)")
    }

    private var label: String {
        switch state {
        case .notConfigured: L10n.tr("Set up iPhone")
        case .ready: L10n.tr("Ready")
        case .connecting: L10n.tr("Connecting…")
        case .active: L10n.tr("Session active")
        case .failed: L10n.tr("Connection error")
        }
    }

    private var color: Color {
        switch state {
        case .notConfigured: .orange
        case .ready: .green
        case .connecting: .blue
        case .active: .blue
        case .failed: .red
        }
    }
}
