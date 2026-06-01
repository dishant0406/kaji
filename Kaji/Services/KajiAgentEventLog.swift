import Foundation

enum KajiAgentEventLog {
    private static let lock = NSLock()
    private static let encoder = JSONEncoder()
    private static let fileURL: URL = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeTimestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let directory = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("KajiAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("events-\(safeTimestamp).jsonl")
    }()

    static var path: String { fileURL.path }

    static func record(_ event: String, fields: [String: KajiAgentJSONValue] = [:]) {
        var payload = fields
        payload["timestamp"] = .string(ISO8601DateFormatter().string(from: Date()))
        payload["event"] = .string(event)
        write(payload)
    }

    static func recordFrame(_ frame: KajiAgentRPCFrame, direction: String) {
        record("rpc_frame", fields: [
            "direction": .string(direction),
            "type": .string(frame.type),
            "id": .string(frame.id ?? ""),
            "command": .string(frame.command ?? ""),
            "method": .string(frame.method ?? ""),
            "toolName": .string(frame.toolName ?? ""),
            "toolCallId": .string(frame.toolCallId ?? ""),
            "messageRole": .string(frame.event?.message?.role ?? frame.message ?? ""),
            "assistantEvent": .string(frame.event?.assistantMessageEvent?.type ?? frame.event?.type ?? ""),
            "contentIndex": frame.event?.assistantMessageEvent?.contentIndex.map { .number(Double($0)) } ?? .null,
        ])
    }

    private static func write(_ payload: [String: KajiAgentJSONValue]) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(payload) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data([10]))
    }
}
