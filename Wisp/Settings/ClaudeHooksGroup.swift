import SwiftUI

/// Settings → General → Claude Code: hook status and the confirm-before-write installer.
struct ClaudeHooksGroup: View {
    @State private var status = HookInstaller.status()
    @State private var plan: HookInstaller.Plan?
    @State private var message: String?

    var body: some View {
        SettingsGroup(header: String(localized: "Claude Code")) {
            SettingsRow(title: String(localized: "Hooks")) {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsStatus(text: statusText, color: status == .installed ? Theme.ok : Theme.warning)
                    if let message {
                        Text(message).textSelection(.enabled)
                    }
                }
            } trailing: {
                Button(status == .installed ? String(localized: "Reinstall…") : String(localized: "Install…")) { prepare() }
                    .buttonStyle(.settings)
                    .disabled(status == .noHelper)
            }
            .padding(.vertical, 6)
        }
        .sheet(isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) {
            if let plan { confirmSheet(plan) }
        }
    }

    private var statusText: String {
        switch status {
        case .installed:    String(localized: "Installed")
        case .notInstalled: String(localized: "Not installed")
        case .otherPath:    String(localized: "Points to another wisp")
        case .noHelper:     String(localized: "wisp-hook is missing")
        }
    }

    private func prepare() {
        do {
            plan = try HookInstaller.plan()
        } catch {
            message = error.localizedDescription
        }
    }

    private func confirmSheet(_ plan: HookInstaller.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes to ~/.claude/settings.json")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plan.changes) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: change.kind == .add ? "+" : "−")
                                .foregroundStyle(change.kind == .add ? Color.green : Color.red)
                            Text(change.event).frame(width: 150, alignment: .leading)
                            Text(change.command).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                    }
                    if plan.changes.isEmpty {
                        Text("No changes needed.").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))

            Text("A backup is made first: \(plan.backupURL.lastPathComponent). Other settings stay as they are, but the file is reformatted (keys in alphabetical order).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { self.plan = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Install") { install(plan) }
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
            message = String(localized: "Installed. Backup: \(plan.backupURL.path)")
        } catch {
            message = String(localized: "Failed: \(error.localizedDescription)")
        }
        self.plan = nil
        status = HookInstaller.status()
    }
}
