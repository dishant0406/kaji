import Foundation

final class AgentRunPersistence {
    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct LoadedIndex {
        let runs: [AgentRun]
        let needsRewrite: Bool
    }

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
        if let loaded = loadIndex() {
            try? AgentRunLegacyFileMaintenance().finalize(legacyURL: legacyURL)
            if loaded.needsRewrite {
                try? AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: 200).write(loaded.runs)
            }
            return loaded.runs
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

    private func loadIndex() -> LoadedIndex? {
        let url = rootURL.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let version = (try? JSONDecoder().decode(VersionProbe.self, from: data))?.version ?? 1
        if version == 2, let snapshot = try? JSONDecoder().decode(AgentRunIndexSnapshotV2.self, from: data) {
            return LoadedIndex(runs: snapshot.runs.map(loadRun), needsRewrite: false)
        }
        guard let snapshot = try? JSONDecoder().decode(AgentRunIndexSnapshot.self, from: data) else { return nil }
        let runs = snapshot.runs.map { record in
            var run = record.run
            run.changedFiles = loadChangedFiles(record: record)
            return run
        }
        return LoadedIndex(runs: runs, needsRewrite: true)
    }

    private func loadRun(summary: AgentRunIndexSummary) -> AgentRun {
        let detail = loadDetail(runID: summary.id)
        var run = AgentRun(
            id: summary.id,
            providerID: summary.providerID,
            paneID: summary.paneID,
            projectID: summary.projectID,
            worktreeID: summary.worktreeID,
            worktreePath: summary.worktreePath,
            sessionID: summary.sessionID,
            transcriptPath: summary.transcriptPath,
            sessionUpdatedAt: summary.sessionUpdatedAt,
            title: summary.title,
            status: summary.status,
            sourceConfidence: summary.sourceConfidence,
            changedFiles: detail?.changedFilesPreview ?? [],
            changedFilesAttribution: summary.changedFilesAttribution,
            verification: detail?.verification ?? summary.verification.verification,
            startedAt: summary.startedAt,
            lastEventAt: summary.lastEventAt,
            events: detail?.events ?? [],
            actions: detail?.actions ?? []
        )
        run.changedFiles = loadChangedFiles(
            runID: summary.id,
            manifest: summary.changedFilesManifest,
            fallback: detail?.changedFilesPreview ?? []
        )
        return run
    }

    private func loadDetail(runID: UUID) -> AgentRunDetailSnapshot? {
        let url = rootURL
            .appendingPathComponent("Details", isDirectory: true)
            .appendingPathComponent("\(runID.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentRunDetailSnapshot.self, from: data)
    }

    private func loadChangedFiles(record: AgentRunIndexRecord) -> [AgentChangedFile] {
        loadChangedFiles(runID: record.run.id, manifest: record.changedFilesManifest, fallback: record.run.changedFiles)
    }

    private func loadChangedFiles(
        runID: UUID,
        manifest: AgentRunChangedFilesManifest,
        fallback: [AgentChangedFile]
    ) -> [AgentChangedFile] {
        let manifestURL = changedFilesDirectory(runID: runID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let storedManifest = try? JSONDecoder().decode(AgentRunChangedFilesManifest.self, from: data)
        else {
            return fallback
        }

        var files: [AgentChangedFile] = []
        for index in 0 ..< storedManifest.chunkCount {
            let url = changedFilesDirectory(runID: runID)
                .appendingPathComponent(Self.chunkName(index))
            guard let data = try? Data(contentsOf: url),
                  let chunk = try? JSONDecoder().decode([AgentChangedFile].self, from: data)
            else {
                continue
            }
            files.append(contentsOf: chunk)
        }
        return files.isEmpty && manifest.storedCount > 0 ? fallback : files
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
