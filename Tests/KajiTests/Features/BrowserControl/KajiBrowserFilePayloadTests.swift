import Foundation
import Testing

@testable import Kaji

struct KajiBrowserFilePayloadTests {
    @Test
    func loadsProjectScopedUploadPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("upload.txt")
        try Data("hello".utf8).write(to: file)

        let payload = try KajiBrowserFilePayloads.load(paths: [file.path], projectPath: root.path)

        #expect(payload.count == 1)
        #expect(payload[0]["name"] == "upload.txt")
        #expect(payload[0]["mime"] == "text/plain")
        #expect(payload[0]["base64"] == Data("hello".utf8).base64EncodedString())
    }

    @Test
    func rejectsFilesOutsideProject() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = URL(fileURLWithPath: "/private/var/db/outside.txt")

        #expect(throws: KajiBrowserFilePayloadError.self) {
            try KajiBrowserFilePayloads.load(paths: [outside.path], projectPath: project.path)
        }
    }
}
