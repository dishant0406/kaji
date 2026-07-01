import Foundation

enum KajiAgentEventLog {
    private static let lock = NSLock()
    private static let encoder = JSONEncoder()
    private static let isEnabled = KajiAgentEventLogPolicy.isEnabled(environment: ProcessInfo.processInfo.environment)
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

    private static let writer = KajiAgentEventLogWriter(fileURL: fileURL)

    static var path: String { isEnabled ? fileURL.path : "" }

    static func record(_ event: String, fields: [String: KajiAgentJSONValue] = [:]) {
        guard isEnabled else { return }
        var payload = fields
        payload["timestamp"] = .string(timestamp())
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
        writer.writeLine(data)
    }

    private static func timestamp() -> String {
        KajiAgentEventTimestampFormatter.shared.string(from: Date())
    }
}
