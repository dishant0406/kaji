import Foundation
import FFFWorkerProtocol
import Testing

@testable import Kaji

@Suite("FFF worker isolation", .serialized)
struct FFFWorkerClientTests {
    @Test("worker crash becomes a safe search failure")
    func crashDoesNotReachHostProcess() async throws {
        let executable = try makeCrashWorker()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let backoff = FFFWorkerBackoffRecorder()
        let client = FFFWorkerClient(
            workerURL: { executable },
            libraryURL: { URL(fileURLWithPath: "/tmp/not-loaded-by-crash-fixture") },
            sleep: { backoff.record($0) }
        )

        await #expect(throws: FFFSearchError.self) {
            _ = try await client.send(.searchFiles(projectPath: "/tmp/repo", query: "needle", limit: 20), timeout: 1)
        }
        await #expect(throws: FFFSearchError.self) {
            _ = try await client.send(.searchFiles(projectPath: "/tmp/repo", query: "needle", limit: 20), timeout: 1)
        }

        #expect(backoff.delays == [0.1])
    }

    @Test("worker death while closing an index does not block removal")
    func crashDuringRemoveCountsAsClosed() async throws {
        let executable = try makeCrashWorker()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let client = FFFWorkerClient(
            workerURL: { executable },
            libraryURL: { URL(fileURLWithPath: "/tmp/not-loaded-by-crash-fixture") },
            sleep: { _ in }
        )

        await client.remove(projectPaths: ["/tmp/repo", "/tmp/repo"])
    }

    @Test("JSONL frames reject oversized requests and survive repeated round trips")
    func boundedProtocolStress() throws {
        for index in 0 ..< 2_000 {
            let request = FFFWorkerRequest(
                command: .searchFiles(projectPath: "/tmp/repo", query: "needle-\(index)", limit: 30)
            )
            let encoded = try FFFJSONLineCodec.encode(request, maximumBytes: fffWorkerMaximumRequestBytes)
            let decoded = try JSONDecoder().decode(FFFWorkerRequest.self, from: encoded.dropLast())
            #expect(decoded == request)
        }

        let oversized = FFFWorkerRequest(
            command: .searchFiles(projectPath: "/tmp/repo", query: String(repeating: "x", count: 2_000), limit: 30)
        )
        #expect(throws: FFFWorkerProtocolError.frameTooLarge) {
            try FFFJSONLineCodec.encode(oversized, maximumBytes: 1_024)
        }
    }

    @Test("JSONL reader waits for a split frame without blocking indefinitely")
    func splitFrameRead() throws {
        let pipe = Pipe()
        let request = FFFWorkerRequest(command: .searchFiles(projectPath: "/tmp/repo", query: "needle", limit: 30))
        let encoded = try FFFJSONLineCodec.encode(request, maximumBytes: fffWorkerMaximumRequestBytes)
        let split = encoded.count / 2
        pipe.fileHandleForWriting.write(encoded.prefix(split))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            try? pipe.fileHandleForWriting.write(contentsOf: encoded.suffix(from: split))
        }
        var reader = FFFJSONLineReader(handle: pipe.fileHandleForReading, maximumBytes: fffWorkerMaximumRequestBytes)

        let frame = try reader.nextFrame(timeout: 1)

        #expect(try JSONDecoder().decode(FFFWorkerRequest.self, from: frame) == request)
    }

    @Test("JSONL reader times out on an incomplete frame")
    func incompleteFrameTimesOut() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("{\"partial\":".utf8))
        var reader = FFFJSONLineReader(handle: pipe.fileHandleForReading, maximumBytes: fffWorkerMaximumRequestBytes)

        #expect(throws: FFFWorkerProtocolError.timedOut) {
            try reader.nextFrame(timeout: 0.02)
        }
    }

    private func makeCrashWorker() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("KajiFFFWorker")
        try "#!/bin/sh\nkill -SEGV $$\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }
}

private final class FFFWorkerBackoffRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.withLock { values }
    }

    func record(_ delay: TimeInterval) {
        lock.withLock { values.append(delay) }
    }
}
