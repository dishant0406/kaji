import Foundation
import Testing
@testable import Kaji

struct KajiCodeArchiveExtractorTests {
    @Test
    func extractsExecutableIntoEmptyDestination() async throws {
        let fixture = try KajiCodeArchiveFixture()
        defer { fixture.cleanup() }
        let archive = try fixture.createArchive(entries: ["kajicode": "#!/bin/sh\necho 1.0.0\n"])
        let destination = fixture.root.appendingPathComponent("destination", isDirectory: true)

        let binary = try await KajiCodeArchiveExtractor.extract(
            archiveURL: archive,
            destination: destination,
            fileManager: fixture.fileManager
        )

        #expect(binary.path == destination.appendingPathComponent("kajicode").path)
        #expect(fixture.fileManager.isExecutableFile(atPath: binary.path))
    }

    @Test
    func refusesToOverwriteExistingDestination() async throws {
        let fixture = try KajiCodeArchiveFixture()
        defer { fixture.cleanup() }
        let archive = try fixture.createArchive(entries: ["kajicode": "replacement"])
        let destination = fixture.root.appendingPathComponent("destination", isDirectory: true)
        try fixture.fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let marker = destination.appendingPathComponent("marker")
        try Data("preserve".utf8).write(to: marker)

        await #expect(throws: KajiCodeInstallError.extractFailed("Extraction destination already exists.")) {
            try await KajiCodeArchiveExtractor.extract(
                archiveURL: archive,
                destination: destination,
                fileManager: fixture.fileManager
            )
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "preserve")
    }

    @Test
    func rejectsArchiveWithoutExpectedExecutable() async throws {
        let fixture = try KajiCodeArchiveFixture()
        defer { fixture.cleanup() }
        let archive = try fixture.createArchive(entries: ["other": "content"])

        await #expect(throws: KajiCodeInstallError.missingBinary) {
            try await KajiCodeArchiveExtractor.extract(
                archiveURL: archive,
                destination: fixture.root.appendingPathComponent("destination"),
                fileManager: fixture.fileManager
            )
        }
    }
}

private struct KajiCodeArchiveFixture {
    let fileManager = FileManager.default
    let root: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func createArchive(entries: [String: String]) throws -> URL {
        let source = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        for entry in entries {
            let url = source.appendingPathComponent(entry.key)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(entry.value.utf8).write(to: url)
        }
        let archive = root.appendingPathComponent("\(UUID().uuidString).tar.gz")
        let result = try AIGatewayProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", source.path, "."],
            timeout: 15
        )
        guard result.exitCode == 0 else {
            throw KajiCodeInstallError.extractFailed(result.output)
        }
        return archive
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }
}
