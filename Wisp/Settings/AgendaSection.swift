import SwiftUI

/// Settings → Agenda & weer: which calendars count, how a shift is recognised,
/// the ride to work and the place for the weather.
struct AgendaSection: View {
    @ObservedObject var agenda: AgendaStore
    @ObservedObject var weather: WeatherStore

    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searched = false

    var body: some View {
        Section("Agenda & weer") {
            switch agenda.access {
            case .notAsked:
                LabeledContent("Agenda") {
                    Button("Toegang geven") { agenda.requestAccess() }
                }
            case .denied:
                LabeledContent("Agenda") {
                    Button("Open Systeeminstellingen") { agenda.openPrivacySettings() }
                }
                Text("wisp heeft geen toegang tot je agenda. Zet wisp aan onder Privacy en beveiliging → Agenda's.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .granted:
                calendars
            }

            Stepper(value: $agenda.travelMinutes, in: 1...120) {
                LabeledContent("Reistijd naar je dienst", value: "\(agenda.travelMinutes) min")
            }

            LabeledContent("Weer voor", value: [weather.place.name, weather.place.detail]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            TextField("Andere plaats", text: $query, prompt: Text("Zoek een plaats"))
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
                Text("Geen plaats gevonden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("De agenda komt uit de Agenda-app van macOS en wordt alleen gelezen. Het weer komt van Open-Meteo; alleen de plaats gaat daarheen.")
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
        Picker("Diensten herkennen aan", selection: $agenda.shiftRule) {
            Text("‘\(AgendaStore.shiftWord)’ in de titel").tag(AgendaStore.ShiftRule.titleWord)
            ForEach(agenda.calendars, id: \.calendarIdentifier) { calendar in
                Text("Agenda ‘\(calendar.title)’").tag(AgendaStore.ShiftRule.calendar(calendar.calendarIdentifier))
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
