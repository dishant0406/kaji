import CoreServices
import Foundation

final class GitDirectoryWatcher: @unchecked Sendable {
    private let directoryPath: String
    private let filter: GitDirectoryWatcherPathFilter
    private let queue = DispatchQueue(label: "app.kaji.git-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var handler: (@Sendable () -> Void)?
    private var pendingPaths = Set<String>()

    init?(directoryPath: String, handler: @escaping @Sendable () -> Void) {
        let gitPath = (directoryPath as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitPath) else { return nil }

        self.directoryPath = directoryPath
        filter = GitDirectoryWatcherPathFilter(repoPath: directoryPath)
        self.handler = handler

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directoryPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<GitDirectoryWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
                else { return }
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
                watcher.receive(events: Array(zip(paths, flags)))
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        handler = nil
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func receive(events: [(String, UInt32)]) {
        guard !events.isEmpty else { return }
        guard !GitInternalEventFilter.isDominated(events: events) else { return }
        pendingPaths.formUnion(events.map(\.0))
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingPaths()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func flushPendingPaths() {
        let paths = Array(pendingPaths)
        pendingPaths.removeAll(keepingCapacity: true)
        guard !filter.relevantPaths(from: paths).isEmpty else { return }
        handler?()
    }
}
