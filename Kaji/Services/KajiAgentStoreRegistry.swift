import Foundation

@MainActor
@Observable
final class KajiAgentStoreRegistry {
    static let shared = KajiAgentStoreRegistry()

    private var stores: [KajiAgentStoreKey: KajiAgentStore] = [:]

    private init() {}

    func store(for scope: KajiAgentScope) -> KajiAgentStore {
        let key = KajiAgentStoreKey(scope: scope)
        if let store = stores[key] { return store }
        let store = KajiAgentStore(scope: scope)
        stores[key] = store
        return store
    }

    func stop(projectID: UUID) {
        let keys = stores.keys.filter { $0.projectID == projectID }
        for key in keys {
            stores[key]?.stopProcess()
            stores.removeValue(forKey: key)
        }
    }
}

struct KajiAgentStoreKey: Hashable {
    let projectID: UUID
    let worktreeID: UUID
    let agentID: UUID

    init(scope: KajiAgentScope) {
        projectID = scope.projectID
        worktreeID = scope.worktreeID
        agentID = scope.agentID
    }
}
