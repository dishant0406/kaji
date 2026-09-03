import Foundation
import UniformTypeIdentifiers

struct AskAttachment: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case image
        case pdf
        case text
        case folder
        case archive
        case file
    }

    let id: UUID
    let url: URL
    let name: String
    let kind: Kind

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.kind = Self.kind(for: url)
    }

    private static func kind(for url: URL) -> Kind {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .file }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .pdf) {
            return .pdf
        }
        if type.conforms(to: .plainText) || type.conforms(to: .sourceCode) || type.conforms(to: .json) {
            return .text
        }
        if type.conforms(to: .archive) {
            return .archive
        }
        return .file
    }
}
