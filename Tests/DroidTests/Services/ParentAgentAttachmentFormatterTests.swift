import Foundation
import Testing

@testable import Droid

struct ParentAgentAttachmentFormatterTests {
    @Test
    func promptIncludesAttachedFilePaths() throws {
        let file = try temporaryFile(name: "notes.txt", data: Data("hello".utf8))
        let attachment = AskAttachment(url: file)

        let prompt = ParentAgentAttachmentFormatter.prompt("Review this", attachments: [attachment])

        #expect(prompt.contains("Review this"))
        #expect(prompt.contains("Attached files:"))
        #expect(prompt.contains(file.path))
    }

    @Test
    func imageContextIncludesBase64Data() throws {
        let file = try temporaryFile(name: "image.png", data: Data([1, 2, 3]))

        let context = try #require(ParentAgentAttachmentFormatter.contexts([AskAttachment(url: file)]).first)

        #expect(context.name == "image.png")
        #expect(context.path == file.path)
        #expect(context.kind == "image")
        #expect(context.mimeType == "image/png")
        #expect(context.data == Data([1, 2, 3]).base64EncodedString())
    }

    @Test
    func parentTaskStoresPromptAndAttachmentsSeparately() throws {
        let file = try temporaryFile(name: "security-optimized.png", data: Data([1, 2, 3]))
        let attachment = try #require(ParentAgentAttachmentFormatter.contexts([AskAttachment(url: file)]).first)

        let task = ParentAgentTask(prompt: "what is this image", attachments: [attachment])
        let item = try #require(task.timeline.first)

        #expect(item.detail == "what is this image")
        #expect(!item.detail.contains("Attached files:"))
        #expect(item.attachments == [attachment])
    }

    @Test
    func timelineItemDecodesMissingAttachmentsAsEmpty() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1)
        let json = """
        {
          "id": "\(id.uuidString)",
          "kind": "user",
          "title": "You",
          "detail": "hello",
          "isComplete": true,
          "createdAt": \(date.timeIntervalSinceReferenceDate)
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let item = try decoder.decode(ParentAgentTimelineItem.self, from: json)

        #expect(item.attachments.isEmpty)
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}
