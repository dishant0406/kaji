import Foundation
import UniformTypeIdentifiers

enum FilePreviewKind: String, Codable, Equatable {
    case image
    case pdf
    case audioVideo
    case document
    case archive
    case model3D
    case web
    case quickLook

    var displayName: String {
        switch self {
        case .image: "Image"
        case .pdf: "PDF"
        case .audioVideo: "Media"
        case .document: "Document"
        case .archive: "Archive"
        case .model3D: "3D Model"
        case .web: "Web"
        case .quickLook: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .audioVideo: "play.rectangle"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .model3D: "cube"
        case .web: "globe"
        case .quickLook: "eye"
        }
    }
}

enum FilePreviewClassifier {
    private static let textExtensions: Set<String> = [
        "c", "cc", "conf", "cpp", "css", "csv", "env", "go", "h", "hpp", "html", "js", "json", "jsonc", "jsx",
        "log", "m", "md", "markdown", "mm", "plist", "py", "rb", "rs", "sh", "sql", "swift", "toml", "ts", "tsx",
        "txt", "xml", "yaml", "yml",
    ]

    private static let documentExtensions: Set<String> = [
        "doc", "docx", "key", "numbers", "pages", "ppt", "pptx", "rtf", "xls", "xlsm", "xlsx",
    ]

    private static let archiveExtensions: Set<String> = ["7z", "bz2", "gz", "rar", "tar", "tgz", "xz", "zip"]
    private static let modelExtensions: Set<String> = ["dae", "obj", "scn", "stl", "usdz"]
    private static let webPreviewExtensions: Set<String> = ["svg"]

    static func previewKind(for filePath: String) -> FilePreviewKind? {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return nil
        }
        if webPreviewExtensions.contains(ext) {
            return .web
        }
        if documentExtensions.contains(ext) {
            return .document
        }
        if archiveExtensions.contains(ext) {
            return .archive
        }
        if modelExtensions.contains(ext) {
            return .model3D
        }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if isText(type) {
            return nil
        }
        if type.conforms(to: .pdf) {
            return .pdf
        }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .movie) || type.conforms(to: .audio) || type.conforms(to: .audiovisualContent) {
            return .audioVideo
        }
        if type.conforms(to: .archive) {
            return .archive
        }
        return .quickLook
    }

    private static func isText(_ type: UTType) -> Bool {
        type.conforms(to: .text)
            || type.conforms(to: .sourceCode)
            || type.conforms(to: .script)
            || type.conforms(to: .json)
            || type.conforms(to: .xml)
            || type.conforms(to: .propertyList)
    }
}
