import SwiftUI

/// Settings → System: Location access, which macOS requires for the Wi-Fi name.
struct SystemSection: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        Section("System") {
            LabeledContent("Wi‑Fi name") {
                if stats.locationAllowed {
                    Text("Shown")
                } else {
                    Button("Allow…") { stats.requestWiFiName() }
                }
            }
            Text("macOS gives apps the name of your Wi‑Fi network only with Location access. wisp uses it for nothing else and never reads where you are.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { stats.refreshWiFi() }
    }
}
