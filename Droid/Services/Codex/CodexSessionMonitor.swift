import Foundation
import os

private let logger = Logger(subsystem: "app.droid", category: "CodexSessionMonitor")

final class CodexSessionMonitor: @unchecked Sendable {
    static let shared = CodexSessionMonitor()

    private struct FileState {
        var offset: UInt64
        var partialLine: String
        var context: CodexSessionEventParser.FileContext
    }

    private let queue = DispatchQueue(label: "app.droid.codex-session-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var fileStates: [String: FileState] = [:]
    private var seenTurnIDs: [String: Date] = [:]

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

    private func startPolling() {
        guard timer == nil else { return }
        let rootURL = CodexSessionPathResolver.sessionsRootURL()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }

        bootstrapState(rootURL: rootURL)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.0)
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
        fileStates.removeAll()
        seenTurnIDs.removeAll()
    }

    private func bootstrapState(rootURL: URL) {
        for fileURL in recentSessionFiles(rootURL: rootURL) {
            let context = sessionContext(for: fileURL)
            let offset = (try? fileSize(for: fileURL)) ?? 0
            fileStates[fileURL.path] = FileState(offset: offset, partialLine: "", context: context)
        }
    }

    private func poll(rootURL: URL) {
        pruneSeenTurnIDs()
        syncFileStates(rootURL: rootURL)
        for fileURL in recentSessionFiles(rootURL: rootURL) {
            processFile(at: fileURL)
        }
    }

    private func syncFileStates(rootURL: URL) {
        let activePaths = Set(recentSessionFiles(rootURL: rootURL).map(\.path))
        fileStates = fileStates.filter { activePaths.contains($0.key) }
        for fileURL in recentSessionFiles(rootURL: rootURL) where fileStates[fileURL.path] == nil {
            let context = sessionContext(for: fileURL)
            fileStates[fileURL.path] = FileState(offset: 0, partialLine: "", context: context)
        }
    }

    private func recentSessionFiles(rootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else {
            return []
        }

        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        return files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        .prefix(200)
        .map(\.self)
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
        if size == state.offset { return }
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
               let projectID = appState.activeProjectID,
               let key = appState.activeWorktreeKey(for: projectID),
               let context = NotificationFallbackContextResolver.resolve(
                   key: key,
                   appState: appState,
                   worktreeStore: NotificationStore.shared.worktreeStore
               )
            {
                NotificationStore.shared.addWithContext(
                    context: context,
                    source: .aiProvider("codex"),
                    title: "Codex",
                    body: completion.message,
                    appState: appState
                )
                return
            }

            NotificationStore.shared.addDetached(
                source: .aiProvider("codex"),
                title: "Codex",
                body: completion.message
            )
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
