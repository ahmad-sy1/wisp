import SwiftUI

/// Departure (design page 2): when to leave and how on the left, the options on the right.
struct DepartureTab: View {
    @ObservedObject var store: DepartureStore
    @ObservedObject var agenda: AgendaStore = .shared
    var openSettings: () -> Void = {}

    var body: some View {
        if let output = store.output {
            HStack(spacing: 10) {
                Card { TripCard(output: output, store: store) }
                    .frame(width: 332)
                Card {
                    switch output.plan.mode {
                    case .transit: AlternativesCard(output: output, hasKey: store.hasNSKey)
                    case .car: LaterCard(output: output, enabled: store.settings.nowOrLater)
                    case .bike: RainCard(output: output, enabled: store.settings.rainCheck)
                    }
                }
            }
        } else {
            Card { empty.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: WispTab.departure.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            if store.settings.home == nil {
                Text("Add your home address to see when to leave.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                settingsButton(String(localized: "Open Settings"))
            } else if agenda.access != .granted {
                Text("wisp needs your calendar to see where you have to be.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                settingsButton(String(localized: "Open Settings"))
            } else {
                Text("No trip coming up.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func settingsButton(_ title: String) -> some View {
        Button(title) {
            SettingsNavigation.shared.page = .departure
            openSettings()
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - The trip

private struct TripCard: View {
    let output: DepartureOutput
    @ObservedObject var store: DepartureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(header)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ModeSwitch(mode: output.plan.mode) { store.setMode($0) }
            }
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output.minutesUntilLeave == 0 ? "Leave" : "Leave in")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    countdown
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    if let chosen = output.chosen {
                        Text(arrivalText(chosen))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(statusText(chosen))
                            .font(.system(size: 12.5))
                            .foregroundStyle(statusColor(chosen))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            if let chosen = output.chosen, !chosen.legs.isEmpty {
                LegChips(legs: chosen.legs)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: String {
        switch output.plan.kind {
        case .home: String(localized: "HEADING HOME")
        case .event: String(localized: "TO \(output.plan.title.uppercased())")
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if output.minutesUntilLeave == 0 {
            Text("now")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(output.timeUrgency.color)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: "\(output.minutesUntilLeave)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(output.timeUrgency.color)
                Text("min")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func arrivalText(_ chosen: TravelOption) -> String {
        let time = chosen.arrival.clockTime
        return output.plan.kind == .home ? String(localized: "Home \(time)") : String(localized: "There \(time)")
    }

    private func statusText(_ chosen: TravelOption) -> String {
        if output.isLate { return String(localized: "Late") }
        if chosen.trafficMinutes >= DepartureEngine.tightDelay {
            let road = chosen.routeName.map { " \($0)" } ?? ""
            return String(localized: "+\(chosen.trafficMinutes) min traffic\(road)")
        }
        if chosen.delayMinutes > 0 { return String(localized: "+\(chosen.delayMinutes) min delay") }
        return String(localized: "On time")
    }

    private func statusColor(_ chosen: TravelOption) -> Color {
        if output.isLate { return Theme.badge }
        if output.delayUrgency == .normal { return Theme.ok }
        return output.delayUrgency.color
    }
}

private struct ModeSwitch: View {
    let mode: TravelMode
    let choose: (TravelMode) -> Void

    var body: some View {
        SegmentedControl(
            selection: Binding(get: { mode }, set: choose),
            values: TravelMode.allCases,
            label: { .symbol($0.symbol, help: $0.title) },
            height: 26,
            fontSize: 11.5,
            segmentWidth: 30)
    }
}

/// The route as chips with the specific line: loop 6 min › NS spoor 3 › 300 16:04 · halte B.
private struct LegChips: View {
    let legs: [TravelLeg]
    private static let shown = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(legs.prefix(Self.shown).enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                chip(leg)
            }
            if legs.count > Self.shown {
                Text(verbatim: "+\(legs.count - Self.shown)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
    }

    private func chip(_ leg: TravelLeg) -> some View {
        HStack(spacing: 4) {
            badge(leg)
            Text(detail(leg))
                .font(.system(size: 11))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .foregroundStyle(leg.isCancelled ? Theme.badge : Theme.textPrimary)
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.control))
    }

    @ViewBuilder
    private func badge(_ leg: TravelLeg) -> some View {
        let (text, fill, ink) = badgeStyle(leg)
        Text(verbatim: text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 4)
            .frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill))
    }

    private func badgeStyle(_ leg: TravelLeg) -> (String, Color, Color) {
        switch leg.kind {
        case .walk: (String(localized: "walk"), Theme.activeTab, Theme.textSecondary)
        case .drive: (String(localized: "car"), Theme.activeTab, Theme.textSecondary)
        case .bike: (String(localized: "bike"), Theme.activeTab, Theme.textSecondary)
        case .rail where leg.line == "NS": ("NS", Theme.nsYellow, .black)
        case .rail: (leg.line ?? String(localized: "Train"), .white, .black)
        default: (leg.line ?? leg.name, .white, .black)
        }
    }

    private func detail(_ leg: TravelLeg) -> String {
        switch leg.kind {
        case .walk, .drive, .bike:
            return "\(leg.minutes) min"
        case .rail:
            return leg.platform.map { String(localized: "platform \($0)") } ?? (leg.departure?.clockTime ?? "")
        default:
            let time = leg.departure?.clockTime ?? ""
            return leg.platform.map { String(localized: "\(time) · stop \($0)") } ?? time
        }
    }
}

// MARK: - The other card

private struct CardTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
    }
}

private struct AlternativesCard: View {
    let output: DepartureOutput
    let hasKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(text: String(localized: "ALTERNATIVES"))
            if hasKey {
                ForEach(output.alternatives) { option in
                    row(option)
                    if option != output.alternatives.last {
                        Rectangle().fill(Theme.cardBorder).frame(height: 1)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("A total time from Apple Maps. Add an NS key under Integrations for lines, platforms and delays.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ option: TravelOption) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: (option.firstRide?.departure ?? option.departure).clockTime)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(option.isCancelled ? Theme.textSecondary : Theme.textPrimary)
            Text(option.summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Text(option.statusText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(option.isCancelled ? Theme.badge : option.delayMinutes > 0 ? Theme.warning : Theme.ok)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 30)
    }
}

private struct LaterCard: View {
    let output: DepartureOutput
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(text: String(localized: "NOW OR LATER"))
            if enabled, let later = output.later {
                ForEach(later.slots, id: \.offsetMinutes) { slot in
                    HStack {
                        Text(slot.offsetMinutes == 0 ? String(localized: "Now") : String(localized: "In \(slot.offsetMinutes) min"))
                            .font(.system(size: 12.5, weight: later.waitMinutes == slot.offsetMinutes ? .semibold : .regular))
                        Spacer()
                        Text("\(slot.minutes) min")
                            .font(.system(size: 12.5))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(height: 22)
                }
                Spacer(minLength: 0)
                advice(later)
            } else {
                Spacer(minLength: 0)
                Text(output.chosen.map { String(localized: "\($0.minutes) min with traffic") } ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func advice(_ later: LaterAdvice) -> some View {
        Group {
            if let wait = later.waitMinutes {
                Text("Wait \(wait) min, saves \(later.savesMinutes) min")
                    .foregroundStyle(Theme.warning)
            } else {
                Text("Go now, waiting doesn't help")
                    .foregroundStyle(Theme.ok)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
    }
}

private struct RainCard: View {
    let output: DepartureOutput
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: String(localized: "SHOWERS"))
            Spacer(minLength: 0)
            if !enabled {
                Text("The rain check is off in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else if let starts = output.rain?.startsInMinutes {
                Label {
                    Text("Rain in \(starts) min")
                        .font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "cloud.rain").foregroundStyle(Theme.rain)
                }
                Text(advice(starts: starts))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label {
                    Text("Dry on the way")
                        .font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "sun.max").foregroundStyle(Theme.ok)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help("Rain from Buienradar or Open-Meteo")
    }

    private func advice(starts: Int) -> String {
        if let dry = output.rain?.dryInMinutes { return String(localized: "Go now or wait \(dry) min") }
        return String(localized: "It stays wet for now")
    }
}
