import SwiftUI

/// Agenda & weather (board 3): today's timeline on the left, the weather and the
/// departure for your next shift on the right. Ticks once a minute, only while visible.
struct AgendaTab: View {
    @ObservedObject var agenda: AgendaStore
    @ObservedObject var weather: WeatherStore

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = AgendaClock.now(context.date)
            HStack(spacing: 10) {
                Card { Timeline(agenda: agenda, now: now) }
                    .frame(width: 348)

                VStack(spacing: 10) {
                    Card { WeatherCard(weather: weather) }
                    Card { DepartureCard(shift: agenda.nextShift(after: now),
                                         travelMinutes: agenda.travelMinutes,
                                         travelMode: agenda.travelMode,
                                         report: weather.report, now: now) }
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
            AgendaMessage(text: String(localized: "See what's on your calendar today."),
                          action: (String(localized: "Give access"), { agenda.requestAccess() }))
        case .denied:
            AgendaMessage(text: String(localized: "wisp has no access to your calendar."),
                          action: (String(localized: "Open System Settings"), { agenda.openPrivacySettings() }))
        case .granted where agenda.events.isEmpty && agenda.tomorrow.isEmpty:
            AgendaMessage(text: String(localized: "Nothing planned today."))
        case .granted:
            list
        }
    }

    private var list: some View {
        let allDay = agenda.events.filter(\.isAllDay)
        let timed = agenda.events.filter { !$0.isAllDay }
        let past = timed.filter { $0.isPast(at: now) }
        // What is on right now gets its own card, just above the "nu" line.
        let ongoing = timed.filter { $0.isOngoing(at: now) }
        let coming = timed.filter { $0.start > now }
        let next = coming.first
        // Once nothing is left today, a peek at how tomorrow starts.
        let peek = ongoing.isEmpty && coming.isEmpty ? Self.firstOf(agenda.tomorrow) : []

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allDay) { EventRow(event: $0, now: now, countdown: false) }
                    ForEach(past) { EventRow(event: $0, now: now, countdown: false) }
                    ForEach(ongoing) { NowCard(event: $0, now: now) }
                    NowLine(now: now).id(NowLine.anchor)
                    ForEach(coming) { EventRow(event: $0, now: now, countdown: $0.id == next?.id) }
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
    /// Show "in 2h 55m" (only the next event does).
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
            if countdown {
                Text("in \(Self.duration(from: now, to: event.start))")
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
    }

    private var timeLabel: String {
        if event.isAllDay { return String(localized: "all day") }
        if event.start == event.end { return event.start.clockTime }
        return "\(event.start.clockTime)–\(event.end.clockTime)"
    }

    /// "25m", "2h", "2h 55m".
    static func duration(from: Date, to: Date) -> String {
        let minutes = max(1, Int((to.timeIntervalSince(from) / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "\(m)m") }
        return m == 0 ? String(localized: "\(h)h") : String(localized: "\(h)h \(m)m")
    }
}

/// What is on right now (board 3.1): a raised card with a *NOW* label, the title and the
/// time, how long it still runs, and a bar that fills up as it goes.
private struct NowCard: View {
    let event: AgendaEvent
    let now: Date
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let color = event.isShift ? Theme.warning : prefs.accent.color
        let total = event.end.timeIntervalSince(event.start)
        let done = total > 0 ? now.timeIntervalSince(event.start) / total : 0

        VStack(alignment: .leading, spacing: 9) {
            // A long title pushes the times out rather than getting cut off itself.
            ViewThatFits(in: .horizontal) {
                header(color: color, showTimes: true)
                header(color: color, showTimes: false)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.activeTab)
                    Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, done)))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .padding(.horizontal, 15)
        .padding(.vertical, 4)
    }

    private func header(color: Color, showTimes: Bool) -> some View {
        HStack(spacing: 10) {
            Text("NOW")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color))
                .fixedSize()
            Text(event.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if showTimes {
                Text(verbatim: "\(event.start.clockTime)–\(event.end.clockTime)")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Text("\(EventRow.duration(from: now, to: event.end)) left")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .fixedSize()
        }
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
            Text("now \(now.clockTime)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.badge)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
    }
}

/// "Tomorrow · Friday 30 October", above the peek at tomorrow.
private struct DayHeader: View {
    let day: Date

    var body: some View {
        HStack(spacing: 8) {
            Text("Tomorrow · \(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
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
                    Text(verbatim: "\(Int(report.temperature.rounded()))°")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                    Text(verbatim: "\(weather.place.name) · \(report.description)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(weather.status == .failed ? String(localized: "No weather") : String(localized: "Loading weather…"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(weather.status == .failed ? String(localized: "Open-Meteo can't be reached") : weather.place.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .help("Weather from Open-Meteo")
    }
}

/// "Leave for your shift · 16:25 · 22 min cycling · Dry until 22:00".
private struct DepartureCard: View {
    let shift: AgendaEvent?
    let travelMinutes: Int
    let travelMode: AgendaStore.TravelMode
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
        shift == nil ? String(localized: "No more shifts today") : String(localized: "Leave for your shift")
    }

    private var headline: String {
        guard let leave else { return report?.rainSummary(at: now) ?? "—" }
        let when = leave <= now ? String(localized: "Now") : leave.clockTime
        return "\(when) · \(travelMode.duration(travelMinutes))"
    }

    private var detail: String? {
        if let shift {
            return report?.rainSummary(at: now) ?? String(localized: "Shift at \(shift.start.clockTime)")
        }
        if let low = report?.low, let high = report?.high {
            return String(localized: "Today \(Int(low.rounded()))° to \(Int(high.rounded()))°")
        }
        return nil
    }
}

// MARK: - Tab bar

/// Right side of the tab bar on the Agenda tab: "Today · Thursday 29 October".
struct AgendaToolbar: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text("Today · \(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// The moment the Agenda tab shows. Debug builds take `-agendaTime 21:30` to pretend
/// it is that time today, so the evening or a running event can be checked any time.
enum AgendaClock {
    static func now(_ date: Date = .now) -> Date {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "agendaTime") {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,
               let pretend = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) {
                return pretend
            }
        }
        #endif
        return date
    }
}
