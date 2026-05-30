import Foundation

actor AgentRunPersistenceWriter {
    private let rootURL: URL
    private let chunkSize: Int
    private var pendingTask: Task<Void, Never>?
    private var pendingRuns: [AgentRun] = []

    init(rootURL: URL, chunkSize: Int = 200) {
        self.rootURL = rootURL
        self.chunkSize = chunkSize
    }

    func scheduleSave(_ runs: [AgentRun]) {
        pendingRuns = runs
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            savePending()
        }
    }

    func save(_ runs: [AgentRun]) {
        pendingTask?.cancel()
        try? diskWriter.write(runs)
    }

    private func savePending() {
        let runs = pendingRuns
        pendingRuns = []
        try? diskWriter.write(runs)
    }

    private var diskWriter: AgentRunPersistenceDiskWriter {
        AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: chunkSize)
    }
}
