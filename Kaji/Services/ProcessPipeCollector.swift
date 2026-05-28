import Foundation

final class ProcessPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private let handle: FileHandle

    init(pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(chunk)
        }
    }

    var data: Data {
        lock.withLock { storage }
    }

    func stop() {
        handle.readabilityHandler = nil
        let remaining = handle.availableData
        if !remaining.isEmpty {
            append(remaining)
        }
    }

    private func append(_ data: Data) {
        lock.withLock {
            storage.append(data)
        }
    }
}
