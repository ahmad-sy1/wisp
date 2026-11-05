import SwiftUI

/// Settings → Departure (design page 4). The notifications live here, and the ride to your
/// shift moved here from Calendar & weather so nothing is set twice.
struct DeparturePage: View {
    @ObservedObject var store: DepartureStore
    @ObservedObject var agenda: AgendaStore
    @State private var changingHome = false

    var body: some View {
        SettingsPage(title: String(localized: "Departure"),
                     note: String(localized: "Your calendar is only read. Travel times come from NS, OVapi and Apple Maps, rain from Buienradar and Open-Meteo. Your home address stays on this Mac and only goes to Apple for routes.")) {
            SettingsGroup(header: String(localized: "Basics")) {
                SettingsRow(String(localized: "Home address"), subtitle: store.settings.home?.name ?? String(localized: "Not set")) {
                    Button(store.settings.home == nil ? "Add" : "Change") { changingHome = true }
                        .buttonStyle(.settings)
                }
                SettingsRow(String(localized: "Default transport")) {
                    Picker("Default transport", selection: $store.settings.defaultMode) {
                        ForEach(TravelMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(String(localized: "Show from"), subtitle: String(localized: "before the end of your last event")) {
                    stepper(value: store.settings.showBeforeEndMinutes, range: 5...60) { store.settings.showBeforeEndMinutes = $0 }
                }
                SettingsRow(String(localized: "Travel time to your shift"), subtitle: String(localized: "Without a home address, or when no route is known")) {
                    stepper(value: agenda.travelMinutes, range: 1...120) { agenda.travelMinutes = $0 }
                }
                if agenda.access != .granted {
                    SettingsRow(String(localized: "Calendar"), subtitle: String(localized: "wisp reads the macOS Calendar app.")) {
                        if agenda.access == .notAsked {
                            Button("Give access") { agenda.requestAccess() }.buttonStyle(.settings)
                        } else {
                            Button("Open System Settings") { agenda.openPrivacySettings() }.buttonStyle(.settings)
                        }
                    }
                }
            }

            SettingsGroup(header: String(localized: "Notifications in the notch")) {
                SettingsToggle(String(localized: "Back home"), subtitle: String(localized: "After your last event with a location"), isOn: $store.settings.returnHome)
                SettingsToggle(String(localized: "Going there"), subtitle: String(localized: "When you have to leave for an event"), isOn: $store.settings.outbound)
                SettingsToggle(String(localized: "Recognise routine"), subtitle: String(localized: "Repeating locations count as trips automatically"), isOn: $store.settings.routine)
                SettingsToggle(String(localized: "Now-or-later advice"), subtitle: String(localized: "Car: wait if that avoids traffic"), isOn: $store.settings.nowOrLater)
                SettingsToggle(String(localized: "Rain check"), subtitle: String(localized: "Bike: warn about showers"), isOn: $store.settings.rainCheck)
            }
        }
        .onAppear { agenda.loadCalendars() }
        .sheet(isPresented: $changingHome) { HomeSheet(store: store) }
    }

    private func stepper(value: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            StepButton(symbol: "minus", help: String(localized: "Shorter")) { set(max(range.lowerBound, value - 5)) }
            Text("\(value) min")
                .font(.system(size: 13))
                .monospacedDigit()
                .frame(minWidth: 52)
            StepButton(symbol: "plus", help: String(localized: "Longer")) { set(min(range.upperBound, value + 5)) }
        }
    }
}

private struct HomeSheet: View {
    @ObservedObject var store: DepartureStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var searching = false
    @State private var notFound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Home address").font(.headline)
            TextField("Home address", text: $address, prompt: Text("Street and number, town"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            if notFound {
                Text("Apple Maps can't find this address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if store.settings.home != nil {
                    Button("Remove") {
                        store.settings.home = nil
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { address = store.settings.home?.name ?? "" }
    }

    private func save() {
        searching = true
        notFound = false
        Task {
            let found = await store.setHome(address)
            searching = false
            if found { dismiss() } else { notFound = true }
        }
    }
}
