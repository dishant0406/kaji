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
            try? AgentRunLegacyFileMaintenance().finalize(legacyURL: legacyURL)
            return snapshot.runs.map { record in
                var run = record.run
                run.changedFiles = loadChangedFiles(record: record)
                return run
            }
        }

        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let runs = try? JSONDecoder().decode([AgentRun].self, from: data)
        else {
            return []
        }

        let migratedRuns = runs.map { run in
            var run = run
            run.changedFiles = AgentChangedFilesSnapshotPolicy.default.capturedFiles(from: run.changedFiles)
            return run
        }
        if (try? AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: 200).write(migratedRuns)) != nil {
            try? AgentRunLegacyFileMaintenance().finalize(legacyURL: legacyURL)
        }
        return migratedRuns
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

    private func loadChangedFiles(record: AgentRunIndexRecord) -> [AgentChangedFile] {
        let runID = record.run.id
        let manifestURL = changedFilesDirectory(runID: runID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(AgentRunChangedFilesManifest.self, from: data)
        else {
            return record.run.changedFiles
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
        return files.isEmpty && record.changedFilesManifest.storedCount > 0 ? record.run.changedFiles : files
    }

    private func changedFilesDirectory(runID: UUID) -> URL {
        rootURL
            .appendingPathComponent("ChangedFiles", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    static func chunkName(_ index: Int) -> String {
        "chunk-\(String(format: "%03d", index)).json"
    }
}
