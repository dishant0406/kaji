import Foundation

@MainActor
extension KajiBrowserControlRegistry {
    func fileUpload(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let files = try KajiBrowserFilePayloads.load(paths: arguments.strings("paths"), projectPath: target.state.projectPath)
        let targetArgs = KajiBrowserTargetArguments(arguments)
        try await target.selectedController?.uploadFiles(target: targetArgs.target, selector: targetArgs.selector, files: files)
        return current(target: target).merging(["uploaded": files.count]) { _, new in new }
    }

    func drop(_ arguments: KajiBrowserControlArguments, target: KajiBrowserSessionTarget) async throws -> [String: Any] {
        let targetArgs = KajiBrowserTargetArguments(arguments)
        let payload = KajiBrowserDropPayloads.load(arguments)
        let files = try KajiBrowserFilePayloads.load(paths: arguments.strings("paths"), projectPath: target.state.projectPath)
        try await target.selectedController?.drop(target: targetArgs.target, selector: targetArgs.selector, data: payload, files: files)
        return current(target: target).merging(["dropped": payload.count + files.count]) { _, new in new }
    }
}

enum KajiBrowserFilePayloads {
    static func load(paths: [String], projectPath: String) throws -> [[String: String]] {
        try paths.map { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let project = URL(fileURLWithPath: projectPath).standardizedFileURL
            guard url.path.hasPrefix(project.path) || url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else {
                throw KajiBrowserFilePayloadError.outsideProject
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 25 * 1024 * 1024 else { throw KajiBrowserFilePayloadError.tooLarge }
            return [
                "name": url.lastPathComponent,
                "mime": mime(for: url),
                "base64": data.base64EncodedString(),
            ]
        }
    }

    private static func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg",
             "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "pdf": "application/pdf"
        case "txt",
             "md": "text/plain"
        case "json": "application/json"
        default: "application/octet-stream"
        }
    }
}

enum KajiBrowserDropPayloads {
    static func load(_ arguments: KajiBrowserControlArguments) -> [[String: String]] {
        arguments.objects("data").map { item in
            [
                "mime": item["mime"] as? String ?? item["type"] as? String ?? "text/plain",
                "value": item["value"] as? String ?? item["text"] as? String ?? "",
            ]
        }
    }
}

enum KajiBrowserFilePayloadError: LocalizedError {
    case outsideProject
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .outsideProject: "file_upload_outside_project"
        case .tooLarge: "file_upload_too_large"
        }
    }
}
