import SwiftUI

/// Agenda & weather (board 3): today's timeline on the left, the weather and the
/// departure for your next shift on the right. Ticks once a minute, only while visible.
struct AgendaTab: View {
    @ObservedObject var agenda: AgendaStore
    @ObservedObject var weather: WeatherStore

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Card { Timeline(agenda: agenda, now: context.date) }
                    .frame(width: 348)

                VStack(spacing: 10) {
                    Card { WeatherCard(weather: weather) }
                    Card { DepartureCard(shift: agenda.nextShift(after: context.date),
                                         travelMinutes: agenda.travelMinutes,
                                         report: weather.report, now: context.date) }
                }
            }
        }
        .onAppear {
            agenda.setVisible(true)
            weather.refreshIfStale()
        }
        .onDisappear { agenda.setVisible(false) }
    }
}

// MARK: - Timeline

private struct Timeline: View {
    @ObservedObject var agenda: AgendaStore
    let now: Date

    var body: some View {
        switch agenda.access {
        case .notAsked:
            AgendaMessage(text: "Zie hier wat er vandaag in je agenda staat.",
                          action: ("Toegang geven", { agenda.requestAccess() }))
        case .denied:
            AgendaMessage(text: "wisp heeft geen toegang tot je agenda.",
                          action: ("Open Systeeminstellingen", { agenda.openPrivacySettings() }))
        case .granted where agenda.events.isEmpty && agenda.tomorrow.isEmpty:
            AgendaMessage(text: "Niets gepland vandaag.")
        case .granted:
            list
        }
    }

    private var list: some View {
        let allDay = agenda.events.filter(\.isAllDay)
        let timed = agenda.events.filter { !$0.isAllDay }
        // The "nu" line goes above the first timed event that hasn't ended yet.
        let split = timed.firstIndex { !$0.isPast(at: now) } ?? timed.count
        let next = timed.first { $0.start > now }
        // Once nothing is left today, a peek at how tomorrow starts.
        let peek = split == timed.count ? Self.firstOf(agenda.tomorrow) : []

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allDay) { EventRow(event: $0, now: now, countdown: false) }
                    ForEach(timed[..<split]) { EventRow(event: $0, now: now, countdown: false) }
                    NowLine(now: now).id(NowLine.anchor)
                    ForEach(timed[split...]) { EventRow(event: $0, now: now, countdown: $0.id == next?.id) }
                    if let first = peek.first {
                        DayHeader(day: first.start)
                        ForEach(peek) { EventRow(event: $0, now: now, countdown: false) }
                    }
                }
                .padding(.vertical, 5)
            }
            .scrollIndicators(.automatic)
            .onAppear { proxy.scrollTo(NowLine.anchor, anchor: .center) }
        }
    }

    /// The first two timed events of the day, or its all-day events when nothing is timed.
    private static func firstOf(_ day: [AgendaEvent]) -> [AgendaEvent] {
        let timed = day.filter { !$0.isAllDay }
        return Array((timed.isEmpty ? day : timed).prefix(2))
    }
}

private struct EventRow: View {
    let event: AgendaEvent
    let now: Date
    /// Show "over 2u 55m" (only the next event does).
    let countdown: Bool

    var body: some View {
        let past = event.isPast(at: now)
        let color = event.isShift ? Theme.warning : event.color

        HStack(spacing: 0) {
            Text(timeLabel)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 85, alignment: .leading)
            Capsule()
                .fill(past ? Theme.textSecondary.opacity(0.35) : color)
                .frame(width: 3, height: 16)
            Text(event.title)
                .font(.system(size: 13, weight: past ? .regular : .semibold))
                .strikethrough(past, color: Theme.textSecondary)
                .foregroundStyle(past ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .padding(.leading, 12)
            Spacer(minLength: 8)
            if event.isOngoing(at: now) {
                Text("nog \(Self.duration(from: now, to: event.end))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else if countdown {
                Text("over \(Self.duration(from: now, to: event.start))")
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
    }

    private var timeLabel: String {
        if event.isAllDay { return "hele dag" }
        if event.start == event.end { return event.start.clockTime }
        return "\(event.start.clockTime)–\(event.end.clockTime)"
    }

    /// "25m", "2u", "2u 55m".
    static func duration(from: Date, to: Date) -> String {
        let minutes = max(1, Int((to.timeIntervalSince(from) / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)u" : "\(h)u \(m)m"
    }
}

/// The red line with the current time, between what's done and what's coming.
private struct NowLine: View {
    static let anchor = "now"
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Theme.badge)
                .frame(width: 6, height: 6)
                .padding(.leading, 3)
            Rectangle()
                .fill(Theme.badge)
                .frame(height: 1)
                .padding(.leading, 8)
            Text("nu \(now.clockTime)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.badge)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
    }
}

/// "Morgen · vrijdag 30 oktober", above the peek at tomorrow.
private struct DayHeader: View {
    let day: Date

    var body: some View {
        HStack(spacing: 8) {
            Text("Morgen · " + day.formatted(
                .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "nl_NL"))))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            Rectangle()
                .fill(Theme.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
    }
}

private struct AgendaMessage: View {
    let text: String
    var action: (String, () -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Weather and departure

private struct WeatherCard: View {
    @ObservedObject var weather: WeatherStore

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: weather.report?.symbol ?? "cloud")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(weather.report == nil ? Theme.textSecondary : Theme.textPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                if let report = weather.report {
                    Text("\(Int(report.temperature.rounded()))°")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                    Text("\(weather.place.name) · \(report.description)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(weather.status == .failed ? "Geen weer" : "Weer laden…")
                        .font(.system(size: 13, weight: .semibold))
                    Text(weather.status == .failed ? "Open-Meteo is niet bereikbaar" : weather.place.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .help("Weer via Open-Meteo")
    }
}

/// "Vertrek voor je dienst · 16:25 · 22 min reizen · Droog tot 22:00".
private struct DepartureCard: View {
    let shift: AgendaEvent?
    let travelMinutes: Int
    let report: WeatherReport?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var leave: Date? {
        shift.map { $0.start.addingTimeInterval(-Double(travelMinutes) * 60) }
    }

    private var label: String {
        shift == nil ? "Geen dienst meer vandaag" : "Vertrek voor je dienst"
    }

    private var headline: String {
        guard let leave else { return report?.rainSummary(at: now) ?? "—" }
        let when = leave <= now ? "Nu" : leave.clockTime
        return "\(when) · \(travelMinutes) min reizen"
    }

    private var detail: String? {
        if let shift {
            return report?.rainSummary(at: now) ?? "Dienst om \(shift.start.clockTime)"
        }
        if let low = report?.low, let high = report?.high {
            return "Vandaag \(Int(low.rounded()))° tot \(Int(high.rounded()))°"
        }
        return nil
    }
}

// MARK: - Tab bar

/// Right side of the tab bar on the Agenda tab: "Vandaag · donderdag 29 oktober".
struct AgendaToolbar: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text("Vandaag · " + context.date.formatted(
                .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "nl_NL"))))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
