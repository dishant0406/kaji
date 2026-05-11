import Foundation

enum AskDirectorySearchService {
    static func options(query: String, fileManager: FileManager = .default) -> [AskDirectoryOption] {
        let expanded = expandHome(query.isEmpty ? "~" : query)
        let url = URL(fileURLWithPath: expanded)
        let parent = query.hasSuffix("/") ? url : url.deletingLastPathComponent()
        let prefix = query.hasSuffix("/") ? "" : url.lastPathComponent.lowercased()
        let children = (try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.compactMap { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            guard prefix.isEmpty || child.lastPathComponent.lowercased().hasPrefix(prefix) else { return nil }
            return AskDirectoryOption(path: child.standardizedFileURL.path)
        }
        .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        .prefix(30)
        .map(\.self)
    }

    static func expandHome(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + path.dropFirst()
    }
}
