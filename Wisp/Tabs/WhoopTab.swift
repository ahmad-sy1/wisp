import SwiftUI

/// WHOOP's tab (board 11.3): recovery, sleep and strain as three equal tiles.
struct WhoopTab: View {
    @ObservedObject var store: WhoopStore
    var openSettings: () -> Void = {}

    private var info: IntegrationInfo { IntegrationCatalog.info(.whoop)! }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            IntegrationTab(
                info: info, status: status(now: context.date), linkTitle: String(localized: "Open WHOOP"),
                link: WhoopStore.appURL
            ) {
                content
            }
        }
        .onAppear { store.syncIfStale() }
    }

    private func status(now: Date) -> IntegrationTabStatus {
        switch store.status {
        case .notConnected:
            return IntegrationTabStatus(tone: .idle, text: String(localized: "Not connected"))
        case .signedOut(let since):
            let time = since.formatted(date: .omitted, time: .shortened)
            return IntegrationTabStatus(tone: .problem, text: String(localized: "Connection lost · since \(time)"))
        case .connecting, .connected:
            if let today = store.today, today.isEmpty {
                return IntegrationTabStatus(tone: .idle, text: String(localized: "Connected · waiting for data"))
            }
            return .synced(store.lastSync, now: now)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.status {
        case .notConnected:
            IntegrationStateCard(
                symbol: "heart", title: String(localized: "Connect WHOOP"),
                message: String(localized: "Your recovery, sleep and strain, from your own WHOOP developer app.")
            ) {
                Button("Connect") { manage() }.buttonStyle(AccentButtonStyle())
            }
        case .signedOut:
            IntegrationStateCard(
                symbol: "powerplug", isProblem: true, title: String(localized: "WHOOP signed wisp out"),
                message: String(localized: "Your sign-in expired or was revoked. Reconnect to see your scores again.")
            ) {
                Button("Manage") { manage() }.buttonStyle(SecondaryButtonStyle())
                Button("Reconnect") { store.reconnect() }.buttonStyle(AccentButtonStyle())
            }
        case .connecting, .connected:
            if let today = store.today, !today.isEmpty {
                metrics(today)
            } else if store.today != nil {
                IntegrationStateCard(
                    symbol: "moon", title: String(localized: "No data yet"),
                    message: String(
                        localized:
                            "WHOOP sends your first scores after you've worn your strap overnight. wisp checks again every 30 minutes.")
                ) {
                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.isSyncing)
                }
            } else {
                Card { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }

    private func metrics(_ today: WhoopToday) -> some View {
        HStack(spacing: 10) {
            IntegrationMetric(
                label: String(localized: "Recovery"),
                value: today.recovery.map { "\($0.score)%" } ?? "–",
                footer: today.recovery.map { String(localized: "HRV \($0.hrv) ms · RHR \($0.restingHeartRate)") }
                    ?? String(localized: "Not scored yet")
            ) {
                if let recovery = today.recovery { RecoveryBars(scores: recovery.recent) }
            }
            IntegrationMetric(
                label: String(localized: "Sleep"),
                value: today.sleep.map { WhoopFormat.duration($0.asleep) } ?? "–",
                footer: today.sleep != nil
                    ? String(localized: "Deep · Light · REM · Awake") : String(localized: "Not scored yet")
            ) {
                if let sleep = today.sleep {
                    SegmentBar(parts: [
                        .init(value: sleep.deep, color: WhoopColors.deep),
                        .init(value: sleep.light, color: WhoopColors.light),
                        .init(value: sleep.rem, color: WhoopColors.rem),
                        .init(value: sleep.awake, color: Theme.trackOff),
                    ])
                }
            }
            IntegrationMetric(
                label: String(localized: "Strain"),
                value: today.strain.map { $0.score.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                footer: strainFooter(today.strain)
            ) {
                if let strain = today.strain {
                    SegmentBar(parts: [.init(value: strain.score, color: WhoopColors.strain)], total: WhoopToday.Strain.maximum)
                }
            }
        }
    }

    private func strainFooter(_ strain: WhoopToday.Strain?) -> String {
        guard let strain else { return String(localized: "Not scored yet") }
        guard let calories = strain.kilocalories else { return String(localized: "Scale 0–21") }
        return String(localized: "\(calories) kcal · scale 0–21")
    }

    private func manage() {
        let navigation = SettingsNavigation.shared
        navigation.page = .integrations
        navigation.openSetup(of: .whoop)
        openSettings()
    }
}

/// The last seven recoveries; only today's takes its zone colour.
private struct RecoveryBars: View {
    let scores: [Int]

    var body: some View {
        GeometryReader { geometry in
            let count = max(scores.count, 1)
            let width = (geometry.size.width - CGFloat(count - 1) * 4) / CGFloat(count)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == scores.count - 1 ? WhoopColors.zone(score) : Theme.trackOff)
                        .frame(width: max(width, 2), height: max(geometry.size.height * CGFloat(score) / 100, 3))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

enum WhoopColors {
    static let deep = Color(hex: 0x5E5CE6)
    static let light = Color(hex: 0x64D2FF)
    static let rem = Color(hex: 0xBF5AF2)
    static let strain = Color(hex: 0x64D2FF)

    static func zone(_ score: Int) -> Color {
        switch RecoveryZone(score) {
        case .green: Theme.ok
        case .yellow: Color(hex: 0xFFD60A)
        case .red: Theme.badge
        }
    }
}
