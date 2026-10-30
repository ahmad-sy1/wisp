import EventKit
import SwiftUI

/// Settings → Calendar & weather (board 10.4): which calendars show in the notch, how a
/// shift is recognised, the ride to work and the place for the weather.
struct CalendarPage: View {
    @ObservedObject var agenda: AgendaStore
    @ObservedObject var weather: WeatherStore
    @State private var showAll = false
    @State private var changingPlace = false

    var body: some View {
        SettingsPage(title: String(localized: "Calendar & weather"),
                     note: String(localized: "Your calendar is only read, never changed. For the weather only the place name goes to Open-Meteo.")) {
            SettingsGroup(header: String(localized: "Calendars in the notch")) {
                calendars
            }

            SettingsGroup(header: String(localized: "Shifts & travel")) {
                SettingsRow(String(localized: "Recognise shifts by")) {
                    Picker("Recognise shifts by", selection: $agenda.shiftRule) {
                        Text("‘\(AgendaStore.shiftWord)’ in the title").tag(AgendaStore.ShiftRule.titleWord)
                        ForEach(agenda.calendars, id: \.calendarIdentifier) { calendar in
                            Text("Calendar ‘\(calendar.title)’").tag(AgendaStore.ShiftRule.calendar(calendar.calendarIdentifier))
                        }
                        // The chosen calendar while the list isn't loaded (no access yet).
                        if case .calendar(let id) = agenda.shiftRule,
                           !agenda.calendars.contains(where: { $0.calendarIdentifier == id }) {
                            Text("A calendar").tag(agenda.shiftRule)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(String(localized: "Travel time to your shift")) {
                    HStack(spacing: 8) {
                        StepButton(symbol: "minus", help: String(localized: "Shorter")) {
                            agenda.travelMinutes = max(1, agenda.travelMinutes - 5)
                        }
                        Text("\(agenda.travelMinutes) min")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .frame(minWidth: 52)
                        StepButton(symbol: "plus", help: String(localized: "Longer")) {
                            agenda.travelMinutes = min(120, agenda.travelMinutes + 5)
                        }
                        Picker("Travel mode", selection: $agenda.travelMode) {
                            ForEach(AgendaStore.TravelMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            SettingsGroup(header: String(localized: "Weather")) {
                SettingsRow(String(localized: "Place"), subtitle: placeName) {
                    Button("Change") { changingPlace = true }
                        .buttonStyle(.settings)
                }
            }
        }
        .onAppear { agenda.loadCalendars() }
        .sheet(isPresented: $changingPlace) { PlaceSheet(weather: weather) }
    }

    @ViewBuilder
    private var calendars: some View {
        switch agenda.access {
        case .notAsked:
            SettingsRow(String(localized: "Calendar"), subtitle: String(localized: "wisp reads the macOS Calendar app.")) {
                Button("Give access") { agenda.requestAccess() }
                    .buttonStyle(.settings)
            }
        case .denied:
            SettingsRow(String(localized: "Calendar"),
                        subtitle: String(localized: "wisp has no access to your calendar. Turn wisp on under Privacy & Security → Calendars.")) {
                Button("Open System Settings") { agenda.openPrivacySettings() }
                    .buttonStyle(.settings)
            }
        case .granted:
            let hidden = agenda.calendars.filter { agenda.hiddenCalendars.contains($0.calendarIdentifier) }
            ForEach(showAll ? agenda.calendars : agenda.calendars.filter { !hidden.contains($0) },
                    id: \.calendarIdentifier) { calendar in
                CalendarRow(calendar: calendar, isOn: Binding(
                    get: { !agenda.hiddenCalendars.contains(calendar.calendarIdentifier) },
                    set: { on in
                        if on { agenda.hiddenCalendars.remove(calendar.calendarIdentifier) }
                        else { agenda.hiddenCalendars.insert(calendar.calendarIdentifier) }
                    }
                ))
            }
            if showAll {
                SettingsLinkRow(title: String(localized: "Show only the calendars in use")) { showAll = false }
            } else if !hidden.isEmpty {
                SettingsLinkRow(title: String(localized: "Show all calendars (\(hidden.count) hidden)")) { showAll = true }
            }
        }
    }

    private var placeName: String {
        [weather.place.name, weather.place.detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(nsColor: calendar.color)).frame(width: 8, height: 8)
            Text(calendar.title).font(.system(size: 13.5))
            Spacer()
            Toggle(calendar.title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 15)
        .frame(height: 41)
    }
}

/// The square − / + buttons for the travel time.
private struct StepButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.control))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Search for another place for the weather.
private struct PlaceSheet: View {
    @ObservedObject var weather: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Place for the weather").font(.headline)
            TextField("Other place", text: $query, prompt: Text("Search for a place"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results, id: \.self) { place in
                        Button {
                            weather.setPlace(place)
                            dismiss()
                        } label: {
                            HStack {
                                Text(place.name)
                                Spacer()
                                Text(place.detail).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if searched {
                Text("No place found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Search") { search() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func search() {
        let name = query
        Task {
            results = await weather.search(name)
            searched = true
        }
    }
}
