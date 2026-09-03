import Foundation

enum KajiAgentEventLogPolicy {
    static func isEnabled(environment: [String: String]) -> Bool {
        guard let rawValue = environment["KAJI_AGENT_EVENT_LOGS"] else { return false }
        return ["1", "true", "yes", "on"].contains(rawValue.lowercased())
    }
}

final class KajiAgentEventTimestampFormatter: @unchecked Sendable {
    static let shared = KajiAgentEventTimestampFormatter()

    private let formatter = ISO8601DateFormatter()
    private let lock = NSLock()

    private init() {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }
}

final class KajiAgentEventLogWriter: @unchecked Sendable {
    private let fileURL: URL
    private let maxBytes: UInt64
    private let lock = NSLock()
    private var handle: FileHandle?
    private var currentBytes: UInt64 = 0

    init(fileURL: URL, maxBytes: UInt64 = 10 * 1024 * 1024) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    deinit {
        try? handle?.close()
    }

    func writeLine(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard openHandle() != nil else { return }
        rotateIfNeeded(incomingBytes: UInt64(data.count) + 1)
        guard let activeHandle = handle else { return }
        try? activeHandle.write(contentsOf: data)
        try? activeHandle.write(contentsOf: Data([10]))
        currentBytes += UInt64(data.count) + 1
    }

    private func openHandle() -> FileHandle? {
        if let handle {
            return handle
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
        currentBytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        _ = try? handle.seekToEnd()
        self.handle = handle
        return handle
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        guard currentBytes + incomingBytes > maxBytes else { return }
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: fileURL)
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        currentBytes = 0
    }
}
