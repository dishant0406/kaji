import Foundation

struct AgentRunPersistenceDiskWriter {
    let rootURL: URL
    let chunkSize: Int

    private let policy = AgentRunPersistencePayloadPolicy()

    func write(_ runs: [AgentRun]) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let records = try runs.map(writeRecord)
        let snapshot = AgentRunIndexSnapshotV2(version: 2, runs: records)
        let data = try encoder.encode(snapshot)
        try writeIfChanged(data, to: rootURL.appendingPathComponent("index.json"))
        try? pruneChangedFilesDirectories(keeping: Set(runs.map(\.id)))
        try? pruneDetailFiles(keeping: Set(runs.map(\.id)))
    }

    private func writeRecord(_ run: AgentRun) throws -> AgentRunIndexSummary {
        let files = AgentChangedFilesSnapshotPolicy.default.capturedFiles(from: run.changedFiles)
        let detail = policy.detail(run: run, files: files)
        let manifest = try writeChangedFiles(runID: run.id, files: files)
        try writeDetail(runID: run.id, detail: detail)
        return AgentRunIndexSummary(run: run, changedFilesManifest: manifest, detail: detail)
    }

    private func writeDetail(runID: UUID, detail: AgentRunDetailSnapshot) throws {
        let directory = rootURL.appendingPathComponent("Details", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(detail)
        try writeIfChanged(data, to: directory.appendingPathComponent("\(runID.uuidString).json"))
    }

    private func writeChangedFiles(
        runID: UUID,
        files: [AgentChangedFile]
    ) throws -> AgentRunChangedFilesManifest {
        let directory = rootURL
            .appendingPathComponent("ChangedFiles", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)

        let chunks = stride(from: 0, to: files.count, by: chunkSize).map { offset in
            Array(files[offset ..< min(offset + chunkSize, files.count)])
        }
        let chunkData = try chunks.map { try encoder.encode($0) }

        let manifest = AgentRunChangedFilesManifest(
            totalCount: files.count,
            storedCount: files.count,
            chunkSize: chunkSize,
            chunkCount: chunks.count
        )
        let manifestData = try encoder.encode(manifest)
        if changedFilesMatch(directory: directory, manifestData: manifestData, chunkData: chunkData) {
            return manifest
        }
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, data) in chunkData.enumerated() {
            try data.write(to: directory.appendingPathComponent(AgentRunPersistence.chunkName(index)), options: .atomic)
        }
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }

    private func changedFilesMatch(directory: URL, manifestData: Data, chunkData: [Data]) -> Bool {
        guard (try? Data(contentsOf: directory.appendingPathComponent("manifest.json"))) == manifestData else { return false }
        for (index, data) in chunkData.enumerated() {
            guard (try? Data(contentsOf: directory.appendingPathComponent(AgentRunPersistence.chunkName(index)))) == data else {
                return false
            }
        }
        return true
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func pruneChangedFilesDirectories(keeping activeRunIDs: Set<UUID>) throws {
        let root = rootURL.appendingPathComponent("ChangedFiles", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let id = UUID(uuidString: directory.lastPathComponent), !activeRunIDs.contains(id) else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func pruneDetailFiles(keeping activeRunIDs: Set<UUID>) throws {
        let root = rootURL.appendingPathComponent("Details", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !activeRunIDs.contains(id) else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}

private struct AgentRunPersistencePayloadPolicy {
    private let maxEventTextLength = 500
    private let maxActionMessageLength = 300
    private let maxVerificationOutputLength = 4000
    private let maxChangedFilesPreview = 5

    func detail(run: AgentRun, files: [AgentChangedFile]) -> AgentRunDetailSnapshot {
        AgentRunDetailSnapshot(
            events: run.events.map(normalizedEvent),
            actions: run.actions.map(normalizedAction),
            verification: normalizedVerification(run.verification),
            changedFilesPreview: Array(files.prefix(maxChangedFilesPreview))
        )
    }

    private func normalizedEvent(_ event: AgentRunEvent) -> AgentRunEvent {
        AgentRunEvent(
            id: event.id,
            kind: event.kind,
            label: event.label,
            text: capped(event.text, max: maxEventTextLength),
            timestamp: event.timestamp
        )
    }

    private func normalizedAction(_ action: AgentRunActionRecord) -> AgentRunActionRecord {
        AgentRunActionRecord(
            id: action.id,
            kind: action.kind,
            status: action.status,
            message: capped(action.message, max: maxActionMessageLength),
            timestamp: action.timestamp
        )
    }

    private func normalizedVerification(_ verification: AgentVerification) -> AgentVerification {
        AgentVerification(
            status: verification.status,
            command: verification.command,
            output: verification.output.map { capped($0, max: maxVerificationOutputLength) },
            updatedAt: verification.updatedAt
        )
    }

    private func capped(_ value: String, max: Int) -> String {
        guard value.count > max else { return value }
        return String(value.prefix(max))
    }
}
