import Foundation

enum AskMentionSearchService {
    static func options(query: String, projectPath: String) async -> [AskMentionOption] {
        let files = await FileSearchService.search(query: query, in: projectPath)
        var seenFolders = Set<String>()
        let fileOptions = files.map { AskMentionOption(path: $0.relativePath, kind: .file) }
        let folderOptions = files.compactMap { result -> AskMentionOption? in
            let folder = URL(fileURLWithPath: result.relativePath).deletingLastPathComponent().path
            guard folder != ".", !seenFolders.contains(folder) else { return nil }
            seenFolders.insert(folder)
            return AskMentionOption(path: folder, kind: .folder)
        }
        return Array((folderOptions + fileOptions).prefix(30))
    }
}
