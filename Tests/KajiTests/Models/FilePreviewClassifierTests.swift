import Testing

@testable import Kaji

struct FilePreviewClassifierTests {
    @Test
    func routesCodeAndMarkdownToEditor() {
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/App.swift") == nil)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/README.md") == nil)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/data.json") == nil)
    }

    @Test
    func routesMediaAndDocumentsToPreview() {
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/image.png") == .image)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/manual.pdf") == .pdf)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/sheet.xlsx") == .document)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/archive.zip") == .archive)
        #expect(FilePreviewClassifier.previewKind(for: "/tmp/icon.svg") == .web)
    }
}
