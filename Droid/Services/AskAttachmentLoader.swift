import AppKit
import UniformTypeIdentifiers

enum AskAttachmentLoader {
    @MainActor
    static func openPanel() -> [AskAttachment] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.item]
        return panel.runModal() == .OK ? panel.urls.map { AskAttachment(url: $0) } : []
    }

    @MainActor
    static func attachments(from pasteboard: NSPasteboard = .general) -> [AskAttachment] {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let fileAttachments = fileURLs.map { AskAttachment(url: $0) }
        if !fileAttachments.isEmpty { return fileAttachments }
        guard let image = NSImage(pasteboard: pasteboard), let url = save(image: image) else { return [] }
        return [AskAttachment(url: url)]
    }

    private static func save(image: NSImage) -> URL? {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let directory = DroidFileStorage.fileURL(filename: "ask-attachments").deletingPathExtension()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
