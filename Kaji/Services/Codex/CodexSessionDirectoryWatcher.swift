import CoreServices
import Foundation

final class CodexSessionDirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void

    init?(rootURL: URL, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return nil }
        self.queue = queue
        self.onChange = onChange

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, _, _, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<CodexSessionDirectoryWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                watcher.scheduleChange()
            },
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        pendingWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [onChange] in
            onChange()
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
