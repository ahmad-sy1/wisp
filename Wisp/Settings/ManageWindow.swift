import AppKit
import SwiftUI

/// Connects the one Manage window to the service it is opened for.
struct ManageIntegrationOverlay: View {
    let id: IntegrationID
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        if let spec = IntegrationCatalog.manageSpec(for: id) {
            ModalBackdrop(close: close) {
                ManageWindow(spec: spec, close: close).id(id)
            }
        }
    }

    private func close() {
        navigation.managingIntegration = nil
    }
}

/// Boards 10.3.2 and 10.3.3. A key is checked first and only stored when it works; to change
/// one, disconnect and fill it in again.
private struct ManageWindow: View {
    let spec: ManageSpec
    let close: () -> Void

    @ObservedObject private var mail = MailStore.shared
    @ObservedObject private var departure = DepartureStore.shared
    @State private var phase = ManagePhase.idle
    /// Read when something changes, not on every keystroke: it comes from the Keychain.
    @State private var account = ManageAccount()
    @State private var values: [String: String] = [:]
    @State private var task: Task<Void, Never>?
    @State private var keys = WindowKeyMonitor()
    @State private var confirmingDisconnect = false

    #if DEBUG
        /// `-manageState empty|checking|failed` draws that state, for snapshots.
        private var demoState: String? { UserDefaults.standard.string(forKey: "manageState") }
    #else
        private var demoState: String? { nil }
    #endif

    private var isConnected: Bool { account.isConnected }

    private var shownPhase: ManagePhase {
        guard let demoState else { return phase }
        switch demoState {
        case "checking": return .checking
        case "failed": return spec.phase(after: .rejected)
        default: return .idle
        }
    }

    private var pill: IntegrationStatus { spec.status(phase: shownPhase, account: account) }

    private var summary: String { spec.summary(phase: shownPhase, account: account) }

    /// Looks up what is stored for this service.
    private func reloadAccount() {
        guard demoState == nil else { return }
        switch spec.info.id {
        case .gmail:
            let health: ManageAccount.Health
            switch mail.status {
            case .connecting: health = .connecting
            case .failed(let message): health = .failed(message)
            case .connected, .notConfigured: health = .healthy
            }
            let address = mail.address
            account = ManageAccount(
                isConnected: mail.isConfigured, health: health,
                summary: String(localized: "Connected as \(address ?? "")"), address: address)
        case .ns:
            account = ManageAccount(
                isConnected: departure.hasNSKey,
                summary: String(localized: "Connected · key ending in \(departure.nsKeySuffix)"))
        case .github:
            account = ManageAccount()
        }
    }

    private var canConnect: Bool { spec.canConnect(values) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(spec.fields) { field($0) }
                Spacer(minLength: 10)
                help
                HStack(spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 11))
                    Text(spec.privacy)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            buttons
        }
        .frame(width: 460, height: 500)
        .modalSurface()
        .confirmationDialog(
            String(localized: "Disconnect \(spec.info.name)?"), isPresented: $confirmingDisconnect
        ) {
            Button("Disconnect", role: .destructive, action: disconnect)
        } message: {
            Text("wisp disconnects and deletes what you entered from your Keychain.")
        }
        .onAppear {
            keys.start(handle)
            reloadAccount()
        }
        .onChange(of: mail.status) { _, _ in reloadAccount() }
        .onChange(of: departure.hasNSKey) { _, _ in reloadAccount() }
        .onDisappear {
            keys.stop()
            task?.cancel()
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ServiceIcon(letters: spec.info.letters, color: Color(hex: spec.info.tint), size: .modal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: spec.info.name).font(.system(size: 16, weight: .semibold))
                    StatusPill(kind: pill)
                }
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Close")
            }
            Text(summary)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func field(_ field: ManageField) -> some View {
        FormField(
            label: field.label,
            text: binding(for: field),
            prompt: field.placeholder,
            isSecret: field.isSecret,
            error: error(for: field),
            isLocked: isConnected || shownPhase == .checking,
            isMasked: isConnected && field.isSecret)
    }

    private func binding(for field: ManageField) -> Binding<String> {
        Binding(
            get: {
                if isConnected, field.id == ManageSpec.addressField { return account.address ?? "" }
                return values[field.id] ?? ""
            },
            set: {
                values[field.id] = $0
                if case .failed = phase { phase = .idle }
            })
    }

    private func error(for field: ManageField) -> String? {
        if case .failed(let message, field.id) = shownPhase { return message }
        return nil
    }

    private var help: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.info)
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    if let url = URL(string: spec.helpURL) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 3) {
                        Text(spec.helpTitle)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.info)
                }
                .buttonStyle(.plain)
                .focusable(false)
                Text(spec.helpText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 8) {
            if isConnected {
                Button("Disconnect") { confirmingDisconnect = true }.buttonStyle(DangerButtonStyle(height: Theme.windowButtonHeight))
                Spacer()
                Button("Done", action: close).buttonStyle(AccentButtonStyle(height: Theme.windowButtonHeight))
            } else {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(SecondaryButtonStyle(height: Theme.windowButtonHeight))
                primary
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    @ViewBuilder private var primary: some View {
        switch shownPhase {
        case .checking:
            Button {
            } label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking…")
                }
            }
            .buttonStyle(SecondaryButtonStyle(height: Theme.windowButtonHeight))
            .disabled(true)
        case .failed:
            Button("Try again", action: start)
                .buttonStyle(AccentButtonStyle(height: Theme.windowButtonHeight))
                .disabled(!canConnect && demoState == nil)
        case .idle:
            Button("Connect", action: start)
                .buttonStyle(AccentButtonStyle(height: Theme.windowButtonHeight))
                .disabled(!canConnect)
        }
    }

    // MARK: - Actions

    private func cancel() {
        task?.cancel()
        close()
    }

    private func disconnect() {
        switch spec.info.id {
        case .gmail: mail.disconnect()
        case .ns: departure.setNSKey(nil)
        case .github: break
        }
        values = [:]
        phase = .idle
    }

    private func start() {
        guard canConnect, phase != .checking else { return }
        phase = .checking
        let entered = values
        task = Task {
            let result = await verifyAndSave(entered)
            guard !Task.isCancelled else { return }
            if result == .idle { values = [:] }
            phase = result
        }
    }

    /// Nothing is stored unless the service accepts it and the window is still open.
    private func verifyAndSave(_ entered: [String: String]) async -> ManagePhase {
        let check: CredentialCheck
        switch spec.info.id {
        case .gmail:
            let address = (entered[ManageSpec.addressField] ?? "").trimmingCharacters(in: .whitespaces)
            let password = (entered[ManageSpec.passwordField] ?? "").replacingOccurrences(of: " ", with: "")
            check = await mail.check(address: address, appPassword: password)
            if check == .accepted, !Task.isCancelled { mail.connect(address: address, appPassword: password) }
        case .ns:
            let key = (entered[ManageSpec.keyField] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            check = await NSTravelProvider(key: key).checkKey()
            if check == .accepted, !Task.isCancelled { departure.setNSKey(key) }
        case .github:
            check = .unreachable
        }
        return spec.phase(after: check)
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 53:
            cancel()
            return true
        case 36, 76:
            if isConnected {
                close()
            } else {
                start()
            }
            return true
        default:
            return false
        }
    }
}
