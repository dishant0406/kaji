import Foundation

struct AgentRunPersistenceDiskWriter {
    let rootURL: URL
    let chunkSize: Int

    func write(_ runs: [AgentRun]) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let records = try runs.map(writeRecord)
        let snapshot = AgentRunIndexSnapshot(version: 1, runs: records)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: rootURL.appendingPathComponent("index.json"), options: .atomic)
    }

    private func writeRecord(_ run: AgentRun) throws -> AgentRunIndexRecord {
        let files = AgentChangedFilesSnapshotPolicy.default.capturedFiles(from: run.changedFiles)
        let manifest = try writeChangedFiles(runID: run.id, files: files)
        var indexedRun = run
        indexedRun.changedFiles = Array(files.prefix(20))
        return AgentRunIndexRecord(run: indexedRun, changedFilesManifest: manifest)
    }

    private func writeChangedFiles(
        runID: UUID,
        files: [AgentChangedFile]
    ) throws -> AgentRunChangedFilesManifest {
        let directory = rootURL
            .appendingPathComponent("ChangedFiles", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let chunks = stride(from: 0, to: files.count, by: chunkSize).map { offset in
            Array(files[offset ..< min(offset + chunkSize, files.count)])
        }

        for (index, chunk) in chunks.enumerated() {
            let data = try JSONEncoder().encode(chunk)
            try data.write(
                to: directory.appendingPathComponent(AgentRunPersistence.chunkName(index)),
                options: .atomic
            )
        }

        let manifest = AgentRunChangedFilesManifest(
            totalCount: files.count,
            storedCount: files.count,
            chunkSize: chunkSize,
            chunkCount: chunks.count
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }
}
