import Foundation
import Testing
@testable import Kaji

struct KajiAgentEventLogPolicyTests {
    @Test
    func eventLogIsDisabledByDefault() {
        #expect(!KajiAgentEventLogPolicy.isEnabled(environment: [:]))
    }

    @Test
    func eventLogAcceptsExplicitEnableValues() {
        #expect(KajiAgentEventLogPolicy.isEnabled(environment: ["KAJI_AGENT_EVENT_LOGS": "1"]))
        #expect(KajiAgentEventLogPolicy.isEnabled(environment: ["KAJI_AGENT_EVENT_LOGS": "true"]))
        #expect(KajiAgentEventLogPolicy.isEnabled(environment: ["KAJI_AGENT_EVENT_LOGS": "on"]))
    }

    @Test
    func writerCapsLogFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KajiAgentEventLogWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("events.jsonl")
        let writer = KajiAgentEventLogWriter(fileURL: fileURL, maxBytes: 12)
        writer.writeLine(Data("1234567890".utf8))
        writer.writeLine(Data("abcdef".utf8))

        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size <= 12)
    }
}
