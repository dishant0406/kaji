import Foundation

final class AgentRunPersistence {
    private let rootURL: URL
    private let legacyURL: URL
    private let writer: AgentRunPersistenceWriter

    init(
        rootURL: URL = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("AgentRuns", isDirectory: true),
        legacyURL: URL = KajiFileStorage.fileURL(filename: "agent-runs.json")
    ) {
        self.rootURL = rootURL
        self.legacyURL = legacyURL
        writer = AgentRunPersistenceWriter(rootURL: rootURL)
    }

    func loadRuns() -> [AgentRun] {
        if let snapshot = loadIndex() {
            return snapshot.runs.map { record in
                var run = record.run
                run.changedFiles = loadChangedFiles(runID: run.id)
                return run
            }
        }

        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let runs = try? JSONDecoder().decode([AgentRun].self, from: data)
        else {
            return []
        }

        backupLegacyFile()
        return runs.map { run in
            var run = run
            run.changedFiles = AgentChangedFilesSnapshotPolicy.default.capturedFiles(from: run.changedFiles)
            return run
        }
    }

    func scheduleSave(_ runs: [AgentRun]) {
        let writer = writer
        Task {
            await writer.scheduleSave(runs)
        }
    }

    func saveImmediately(_ runs: [AgentRun]) async {
        await writer.save(runs)
    }

    func saveSynchronously(_ runs: [AgentRun]) {
        try? AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: 200).write(runs)
    }

    private func loadIndex() -> AgentRunIndexSnapshot? {
        let url = rootURL.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentRunIndexSnapshot.self, from: data)
    }

    private func loadChangedFiles(runID: UUID) -> [AgentChangedFile] {
        let manifestURL = changedFilesDirectory(runID: runID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(AgentRunChangedFilesManifest.self, from: data)
        else {
            return []
        }

        var files: [AgentChangedFile] = []
        for index in 0 ..< manifest.chunkCount {
            let url = changedFilesDirectory(runID: runID)
                .appendingPathComponent(Self.chunkName(index))
            guard let data = try? Data(contentsOf: url),
                  let chunk = try? JSONDecoder().decode([AgentChangedFile].self, from: data)
            else {
                continue
            }
            files.append(contentsOf: chunk)
        }
        return files
    }

    private func changedFilesDirectory(runID: UUID) -> URL {
        rootURL
            .appendingPathComponent("ChangedFiles", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    private func backupLegacyFile() {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = legacyURL.deletingLastPathComponent()
            .appendingPathComponent("agent-runs.legacy-\(stamp).json")
        try? FileManager.default.copyItem(at: legacyURL, to: backupURL)
    }

    static func chunkName(_ index: Int) -> String {
        "chunk-\(String(format: "%03d", index)).json"
    }
}
