import Foundation

/// How an integration's connection is doing. No value means nothing is stored for it.
enum IntegrationConnection: Equatable, Sendable {
    case connecting
    case connected(String)
    case problem(String)
}

enum IntegrationRowState: Equatable, Sendable {
    case notSetUp
    case connection(IntegrationConnection)

    var needsAttention: Bool {
        switch self {
        case .notSetUp, .connection(.problem): true
        case .connection: false
        }
    }
}

struct IntegrationRowModel: Identifiable, Equatable, Sendable {
    let info: IntegrationInfo
    let state: IntegrationRowState

    var id: IntegrationID { info.id }
}

/// What Settings → Integrations and the sidebar show (boards 10.3.4, 10.10).
enum IntegrationList {
    /// Everything added or connected, by name.
    static func rows(
        of items: [IntegrationInfo] = IntegrationCatalog.all,
        added: Set<IntegrationID>,
        connections: [IntegrationID: IntegrationConnection]
    ) -> [IntegrationRowModel] {
        items
            .compactMap { info -> IntegrationRowModel? in
                if let connection = connections[info.id] {
                    return IntegrationRowModel(info: info, state: .connection(connection))
                }
                return added.contains(info.id) ? IntegrationRowModel(info: info, state: .notSetUp) : nil
            }
            .sorted { $0.info.name.localizedStandardCompare($1.info.name) == .orderedAscending }
    }

    /// Connected services with choices of their own get a place in the sidebar.
    static func sidebarRows(_ rows: [IntegrationRowModel]) -> [IntegrationRowModel] {
        rows.filter { $0.info.hasOptions && $0.state != .notSetUp }
    }
}
