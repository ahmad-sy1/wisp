import SwiftUI

/// Settings → Claude Code: hook status and the confirm-before-write installer.
struct ClaudeHooksSection: View {
    @State private var status = HookInstaller.status()
    @State private var plan: HookInstaller.Plan?
    @State private var removeCoucou = true
    @State private var message: String?

    var body: some View {
        Section("Claude Code") {
            LabeledContent("Hooks") {
                HStack(spacing: 8) {
                    Text(statusText).foregroundStyle(.secondary)
                    Button(status == .installed ? "Opnieuw…" : "Installeren…") { prepare() }
                        .disabled(status == .noHelper)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .sheet(isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) {
            if let plan { confirmSheet(plan) }
        }
    }

    private var statusText: String {
        switch status {
        case .installed:    "Geïnstalleerd"
        case .notInstalled: "Niet geïnstalleerd"
        case .otherPath:    "Verwijst naar een andere wisp"
        case .noHelper:     "wisp-hook ontbreekt"
        }
    }

    private func prepare(removeCoucou: Bool? = nil) {
        if let removeCoucou { self.removeCoucou = removeCoucou }
        do {
            plan = try HookInstaller.plan(removeCoucou: self.removeCoucou)
        } catch {
            message = error.localizedDescription
        }
    }

    private func confirmSheet(_ plan: HookInstaller.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wijzigingen in ~/.claude/settings.json")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plan.changes) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(change.kind == .add ? "+" : "−")
                                .foregroundStyle(change.kind == .add ? Color.green : Color.red)
                            Text(change.event).frame(width: 150, alignment: .leading)
                            Text(change.command).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    }
                    if plan.changes.isEmpty {
                        Text("Geen wijzigingen nodig.").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))

            if plan.hasCoucouHooks {
                Toggle("Oude Coucou-hooks verwijderen", isOn: Binding(
                    get: { removeCoucou },
                    set: { prepare(removeCoucou: $0) }
                ))
            }

            Text("Eerst wordt een back-up gemaakt: \(plan.backupURL.lastPathComponent). Andere instellingen blijven staan; het bestand wordt wel opnieuw opgemaakt (sleutels op alfabet).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Annuleren", role: .cancel) { self.plan = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Installeren") { install(plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.changes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func install(_ plan: HookInstaller.Plan) {
        do {
            try HookInstaller.apply(plan)
            message = "Geïnstalleerd. Back-up: \(plan.backupURL.path)"
        } catch {
            message = "Niet gelukt: \(error.localizedDescription)"
        }
        self.plan = nil
        status = HookInstaller.status()
    }
}
