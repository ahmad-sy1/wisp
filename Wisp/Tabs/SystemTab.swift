import SwiftUI

/// System (board 7): battery, AirPods, CPU and storage side by side.
struct SystemTab: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 10) {
            Card { BatteryCard(stats: stats) }
            Card { BudsCard(buds: stats.buds) }
            Card { CPUCard(stats: stats) }
            Card { StorageCard(storage: stats.storage) }
        }
        .onAppear { stats.setVisible(true) }
        .onDisappear { stats.setVisible(false) }
    }
}

/// Label on top, a big value, then whatever the card shows below it.
private struct StatCard<Value: View, Footer: View>: View {
    let label: String
    @ViewBuilder var value: Value
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            value
            Spacer(minLength: 6)
            footer
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct BigNumber: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 24, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct Bar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

private struct Footer: View {
    let text: String
    var lines = 1

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(lines)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cards

private struct BatteryCard: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        StatCard(label: String(localized: "Battery")) {
            if let battery = stats.battery {
                VStack(alignment: .leading, spacing: 12) {
                    BigNumber(text: "\(battery.percent)%")
                    Bar(fraction: Double(battery.percent) / 100,
                        color: battery.percent <= 20 && !battery.onAC ? Theme.badge : Theme.ok)
                }
            } else {
                BigNumber(text: "—").foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Footer(text: footer)
        }
    }

    private var footer: String {
        guard stats.hasBattery else { return String(localized: "No battery") }
        guard let battery = stats.battery else { return "" }
        if battery.charging {
            guard let minutes = battery.minutes else { return String(localized: "Charging") }
            return String(localized: "Full in \(DurationText.text(minutes))")
        }
        if battery.onAC { return String(localized: "On power") }
        guard let minutes = battery.minutes else { return String(localized: "Working it out…") }
        return String(localized: "\(DurationText.text(minutes)) left")
    }
}

private struct BudsCard: View {
    let buds: SystemStats.Buds?

    var body: some View {
        StatCard(label: buds.map { Self.shortName($0.name) } ?? "AirPods") {
            if buds == nil {
                Image(systemName: "airpodspro")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            if let buds {
                VStack(spacing: 4) {
                    row(String(localized: "Left"), buds.left)
                    row(String(localized: "Right"), buds.right)
                    row(String(localized: "Case"), buds.caseLevel)
                }
            } else {
                Footer(text: String(localized: "Not connected"))
            }
        }
    }

    private func row(_ label: String, _ level: Int?) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 4)
            Text(verbatim: level.map { "\($0)%" } ?? "—")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(level.map { $0 < 20 } == true ? Theme.warning : Theme.textPrimary)
        }
        .font(.system(size: 13))
    }

    /// "AirPods Pro van aatje" → "AirPods Pro": the model, without whose they are.
    static func shortName(_ name: String) -> String {
        for model in ["AirPods Pro", "AirPods Max", "AirPods"] where name.hasPrefix(model) { return model }
        return name
    }
}

private struct CPUCard: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        StatCard(label: "CPU") {
            VStack(alignment: .leading, spacing: 8) {
                BigNumber(text: stats.cpu.map { "\(Int($0.rounded()))%" } ?? "—")
                Sparkline(values: stats.cpuHistory, color: prefs.accent.color)
                    .frame(height: 18)
            }
        } footer: {
            if let top = stats.topProcess {
                Footer(text: String(localized: "\(top.name) uses \(Int(top.percent.rounded()))%"), lines: 2)
            } else {
                Footer(text: String(localized: "Measuring…"))
            }
        }
    }
}

/// A thin line through the last CPU samples, 0–100 %.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(19)
            let x0 = size.width - step * CGFloat(values.count - 1)
            var path = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: x0 + step * CGFloat(i),
                                    y: size.height * (1 - CGFloat(min(100, max(0, value)) / 100)))
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct StorageCard: View {
    let storage: SystemStats.Storage?
    @ObservedObject private var prefs = Preferences.shared

    /// "200 GB", "1.2 TB": whole gigabytes, as the board shows them.
    static func size(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return (gb / 1000).formatted(.number.precision(.fractionLength(1))) + " TB" }
        return "\(Int(gb.rounded())) GB"
    }

    var body: some View {
        StatCard(label: String(localized: "Storage")) {
            if let storage {
                VStack(alignment: .leading, spacing: 12) {
                    BigNumber(text: Self.size(storage.free))
                    Bar(fraction: 1 - Double(storage.free) / Double(max(1, storage.total)), color: prefs.accent.color)
                }
            } else {
                BigNumber(text: "—").foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            if let storage {
                Footer(text: String(localized: "free of \(Self.size(storage.total))"))
            }
        }
    }
}

enum DurationText {
    /// "6h 10m", "25m".
    static func text(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes)m") : String(localized: "\(minutes / 60)h \(minutes % 60)m")
    }
}

/// Right side of the tab bar on the System tab: the Wi-Fi network.
struct SystemToolbar: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: stats.wifiOn ? "wifi" : "wifi.slash")
                .font(.system(size: 12))
            Text(stats.wifiName ?? (stats.wifiOn ? "Wi‑Fi" : String(localized: "Wi‑Fi off")))
                .lineLimit(1)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.textSecondary)
        .help(stats.wifiName == nil && stats.wifiOn
              ? String(localized: "macOS shows the network name only with Location access: Settings → System")
              : "")
    }
}
