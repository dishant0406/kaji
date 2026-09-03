import Foundation
import os

private let logger = Logger(subsystem: "app.kaji", category: "CodexSessionMonitor")

final class CodexSessionMonitor: @unchecked Sendable {
    static let shared = CodexSessionMonitor()
    private static let maxTrackedFiles = 200
    private static let pollingInterval: TimeInterval = 2
    private static let safetyScanInterval: TimeInterval = 60

    private struct FileState {
        var offset: UInt64
        var partialLine: String
        var context: CodexSessionEventParser.FileContext
    }

    private let queue = DispatchQueue(label: "app.kaji.codex-session-monitor", qos: .utility)
    private let scanner = CodexSessionFileScanner()
    private var timer: DispatchSourceTimer?
    private var watcher: CodexSessionDirectoryWatcher?
    private var fileStates: [String: FileState] = [:]
    private var trackedFileURLs: [URL] = []
    private var seenTurnIDs: [String: Date] = [:]
    private var needsFileScan = false
    private var nextSafetyScanDate = Date.distantPast

    private init() {}

    func start() {
        queue.async { [weak self] in
            self?.startPolling()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopPolling()
        }
    }

    func restart() {
        queue.async { [weak self] in
            self?.stopPolling()
            self?.startPolling()
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        let rootURL = CodexSessionPathResolver.sessionsRootURL()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }

        scanFiles(rootURL: rootURL, bootstrap: true)
        watcher = CodexSessionDirectoryWatcher(rootURL: rootURL, queue: queue) { [weak self] in
            self?.needsFileScan = true
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: Self.pollingInterval, leeway: .milliseconds(800))
        timer.setEventHandler { [weak self] in
            self?.poll(rootURL: rootURL)
        }
        self.timer = timer
        timer.resume()
        logger.notice("Started Codex session polling at \(rootURL.path, privacy: .public)")
    }

    private func stopPolling() {
        timer?.cancel()
        timer = nil
        watcher = nil
        fileStates.removeAll()
        trackedFileURLs.removeAll()
        seenTurnIDs.removeAll()
        needsFileScan = false
    }

    private func poll(rootURL: URL) {
        pruneSeenTurnIDs()
        if needsFileScan || Date() >= nextSafetyScanDate {
            scanFiles(rootURL: rootURL, bootstrap: false)
        }
        for fileURL in trackedFileURLs {
            processFile(at: fileURL)
        }
    }

    private func scanFiles(rootURL: URL, bootstrap: Bool) {
        let fileURLs = scanner.recentSessionFiles(rootURL: rootURL, limit: Self.maxTrackedFiles)
        let activePaths = Set(fileURLs.map(\.path))
        fileStates = fileStates.filter { activePaths.contains($0.key) }
        for fileURL in fileURLs where fileStates[fileURL.path] == nil {
            let context = sessionContext(for: fileURL)
            let offset = bootstrap ? (try? fileSize(for: fileURL)) ?? 0 : 0
            fileStates[fileURL.path] = FileState(offset: offset, partialLine: "", context: context)
        }
        trackedFileURLs = fileURLs
        needsFileScan = false
        nextSafetyScanDate = Date().addingTimeInterval(Self.safetyScanInterval)
    }

    private func sessionContext(for fileURL: URL) -> CodexSessionEventParser.FileContext {
        guard let handle = try? FileHandle(forReadingFrom: fileURL),
              let data = try? handle.read(upToCount: 8192),
              let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first
        else {
            return .init()
        }

        var context = CodexSessionEventParser.FileContext()
        _ = CodexSessionEventParser.consume(line: String(firstLine), context: &context)
        return context
    }

    private func processFile(at fileURL: URL) {
        let path = fileURL.path
        var state = fileStates[path] ?? FileState(offset: 0, partialLine: "", context: .init())
        let size = (try? fileSize(for: fileURL)) ?? 0
        if size == state.offset {
            return
        }
        if size < state.offset {
            state.offset = 0
            state.partialLine = ""
            state.context = .init()
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            let data = try handle.readToEnd() ?? Data()
            state.offset = size
            processData(data, state: &state)
            fileStates[path] = state
        } catch {
            logger.error("Failed to read Codex session file \(path, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func processData(_ data: Data, state: inout FileState) {
        guard !data.isEmpty, let text = String(bytes: data, encoding: .utf8) else { return }
        let mergedText = state.partialLine + text
        let hasTrailingNewline = mergedText.hasSuffix("\n")
        var lines = mergedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        state.partialLine = hasTrailingNewline ? "" : lines.popLast() ?? ""

        for line in lines {
            guard let completion = CodexSessionEventParser.consume(line: line, context: &state.context) else { continue }
            dispatch(completion)
        }
    }

    private func dispatch(_ completion: CodexSessionEventParser.Completion) {
        guard seenTurnIDs[completion.turnID] == nil else { return }
        seenTurnIDs[completion.turnID] = Date()
        logger.notice("Dispatching Codex completion for turn \(completion.turnID, privacy: .public)")

        Task { @MainActor in
            guard CodexProvider().isEnabled else { return }
            if let appState = NotificationStore.shared.appState,
               let context = CodexSessionContextResolver.resolve(
                   cwd: completion.cwd,
                   appState: appState,
                   worktreeStore: NotificationStore.shared.worktreeStore
               )
            {
                AgentRunStore.shared.complete(
                    providerID: "codex",
                    projectID: context.projectID,
                    worktreeID: context.worktreeID,
                    message: completion.message
                )
                if let run = AgentRunStore.shared.runs.first(where: { run in
                    run.providerID == "codex" &&
                        run.projectID == context.projectID &&
                        run.worktreeID == context.worktreeID
                }) {
                    ChildAgentFeedStore.shared.append(runID: run.id, kind: .final, text: completion.message)
                }
                return
            }
        }
    }

    private func pruneSeenTurnIDs() {
        let cutoff = Date().addingTimeInterval(-300)
        seenTurnIDs = seenTurnIDs.filter { $0.value > cutoff }
    }

    private func fileSize(for fileURL: URL) throws -> UInt64 {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }
}
