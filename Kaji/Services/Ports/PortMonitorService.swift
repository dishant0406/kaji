import Foundation

@MainActor
@Observable
final class PortMonitorService {
    static let shared = PortMonitorService()

    private(set) var ports: [PortProcessSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var killingPID: Int32?
    private(set) var statusMessage: String?
    private(set) var statusIsError = false

    private init() {}

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                ports = try await PortProcessLister.list()
                statusMessage = nil
                statusIsError = false
            } catch {
                ports = []
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            isRefreshing = false
        }
    }

    func terminate(_ snapshot: PortProcessSnapshot) {
        guard killingPID == nil else { return }
        killingPID = snapshot.pid

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try PortKiller.terminate(pid: snapshot.pid)
                statusMessage = "Terminated pid \(snapshot.pid)."
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            killingPID = nil
            refresh()
        }
    }
}
