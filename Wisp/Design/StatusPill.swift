import SwiftUI

/// Where an integration stands, in the header of a window (board 0.2).
struct StatusPill: View {
    enum Kind {
        case notConnected, checking, failed, connected

        var title: String {
            switch self {
            case .notConnected: String(localized: "Not connected")
            case .checking: String(localized: "Checking")
            case .failed: String(localized: "Couldn't connect")
            case .connected: String(localized: "Connected")
            }
        }

        var color: Color {
            switch self {
            case .notConnected: Theme.textSecondary
            case .checking: Theme.info
            case .failed: Theme.redText
            case .connected: Theme.ok
            }
        }

        var fill: Color {
            switch self {
            case .notConnected: Theme.control
            case .checking: Theme.info.opacity(0.18)
            case .failed: Theme.badge.opacity(0.18)
            case .connected: Theme.ok.opacity(0.16)
            }
        }
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 5) {
            if kind == .checking {
                ProgressView().controlSize(.mini).tint(kind.color)
            } else {
                Circle().fill(kind == .failed ? Theme.badge : kind.color).frame(width: 6, height: 6)
            }
            Text(kind.title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(kind.fill))
    }
}
