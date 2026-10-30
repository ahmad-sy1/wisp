import SwiftUI

/// Settings → Calendar & weather: which calendars count, how a shift is recognised,
/// the ride to work and the place for the weather.
struct AgendaSection: View {
    @ObservedObject var agenda: AgendaStore
    @ObservedObject var weather: WeatherStore

    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searched = false

    var body: some View {
        Section("Calendar & weather") {
            switch agenda.access {
            case .notAsked:
                LabeledContent("Calendar") {
                    Button("Give access") { agenda.requestAccess() }
                }
            case .denied:
                LabeledContent("Calendar") {
                    Button("Open System Settings") { agenda.openPrivacySettings() }
                }
                Text("wisp has no access to your calendar. Turn wisp on under Privacy & Security → Calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .granted:
                calendars
            }

            Stepper(value: $agenda.travelMinutes, in: 1...120) {
                LabeledContent("Travel time to your shift", value: String(localized: "\(agenda.travelMinutes) min"))
            }

            LabeledContent("Weather for", value: [weather.place.name, weather.place.detail]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            TextField("Other place", text: $query, prompt: Text("Search for a place"))
                .onSubmit { search() }
            ForEach(results, id: \.self) { place in
                Button {
                    weather.setPlace(place)
                    results = []
                    query = ""
                    searched = false
                } label: {
                    LabeledContent(place.name, value: place.detail)
                }
                .buttonStyle(.plain)
            }
            if searched && results.isEmpty {
                Text("No place found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("The calendar comes from the macOS Calendar app and is only read. The weather comes from Open-Meteo; only the place is sent there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { agenda.loadCalendars() }
    }

    @ViewBuilder
    private var calendars: some View {
        ForEach(agenda.calendars, id: \.calendarIdentifier) { calendar in
            Toggle(isOn: Binding(
                get: { !agenda.hiddenCalendars.contains(calendar.calendarIdentifier) },
                set: { on in
                    if on { agenda.hiddenCalendars.remove(calendar.calendarIdentifier) }
                    else { agenda.hiddenCalendars.insert(calendar.calendarIdentifier) }
                }
            )) {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: calendar.color)).frame(width: 8, height: 8)
                    Text(calendar.title)
                }
            }
        }
        Picker("Recognise shifts by", selection: $agenda.shiftRule) {
            Text("‘\(AgendaStore.shiftWord)’ in the title").tag(AgendaStore.ShiftRule.titleWord)
            ForEach(agenda.calendars, id: \.calendarIdentifier) { calendar in
                Text("Calendar ‘\(calendar.title)’").tag(AgendaStore.ShiftRule.calendar(calendar.calendarIdentifier))
            }
        }
    }

    private func search() {
        let name = query
        Task {
            results = await weather.search(name)
            searched = true
        }
    }
}
