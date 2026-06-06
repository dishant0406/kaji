import Foundation

enum KajiAgentWorkspacePathResolver {
    static func resolve(_ rawPath: String, rootPath: String) -> String? {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidate = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath)
            : root.appendingPathComponent(rawPath)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else { return nil }
        return resolved.path
    }
}
