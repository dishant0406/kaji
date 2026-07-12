import Foundation

struct FileIcon: Equatable, Hashable {
    let id: String
    let relativePath: String
}

final class FileIconResolver: @unchecked Sendable {
    static let materialIconTheme = FileIconResolver(manifest: .materialIconTheme)

    private let iconDefinitions: [String: FileIconManifest.IconDefinition]
    private let fileNames: [String: String]
    private let fileExtensions: [String: String]
    private let folderNames: [String: String]
    private let folderNamesExpanded: [String: String]
    private let rootFolderNames: [String: String]
    private let rootFolderNamesExpanded: [String: String]
    private let defaultFileIconID: String?
    private let defaultFolderIconID: String?
    private let defaultExpandedFolderIconID: String?
    private let defaultRootFolderIconID: String?
    private let defaultExpandedRootFolderIconID: String?

    init(manifest: FileIconManifest) {
        iconDefinitions = manifest.iconDefinitions
        fileNames = Self.normalizedMap(manifest.fileNames)
        fileExtensions = Self.normalizedMap(manifest.fileExtensions)
        folderNames = Self.normalizedMap(manifest.folderNames)
        folderNamesExpanded = Self.normalizedMap(manifest.folderNamesExpanded)
        rootFolderNames = Self.normalizedMap(manifest.rootFolderNames)
        rootFolderNamesExpanded = Self.normalizedMap(manifest.rootFolderNamesExpanded)
        defaultFileIconID = manifest.file
        defaultFolderIconID = manifest.folder
        defaultExpandedFolderIconID = manifest.folderExpanded ?? manifest.folder
        defaultRootFolderIconID = manifest.rootFolder ?? manifest.folder
        defaultExpandedRootFolderIconID = manifest.rootFolderExpanded ?? manifest.folderExpanded ?? manifest.folder
    }

    func icon(for entry: FileTreeEntry, isExpanded: Bool, isRoot: Bool = false) -> FileIcon? {
        if entry.isDirectory {
            return folderIcon(name: entry.name, relativePath: entry.relativePath, isExpanded: isExpanded, isRoot: isRoot)
        }
        return fileIcon(name: entry.name, relativePath: entry.relativePath)
    }

    func fileIcon(name: String, relativePath: String? = nil) -> FileIcon? {
        let normalizedName = Self.normalizeKey(name)
        let normalizedRelativePath = Self.normalizePath(relativePath)

        if let normalizedRelativePath, let iconID = fileNames[normalizedRelativePath], let icon = icon(id: iconID) {
            return icon
        }
        if let iconID = fileNames[normalizedName], let icon = icon(id: iconID) {
            return icon
        }
        for candidate in extensionCandidates(for: normalizedName) {
            if let iconID = fileExtensions[candidate], let icon = icon(id: iconID) {
                return icon
            }
        }
        return defaultFileIcon()
    }

    func folderIcon(name: String, relativePath: String? = nil, isExpanded: Bool, isRoot: Bool = false) -> FileIcon? {
        let normalizedName = Self.normalizeKey(name)
        let normalizedRelativePath = Self.normalizePath(relativePath)
        let pathMap = folderMap(isExpanded: isExpanded, isRoot: isRoot)
        let fallbackMap = folderMap(isExpanded: false, isRoot: isRoot)

        if let normalizedRelativePath, let iconID = pathMap[normalizedRelativePath], let icon = icon(id: iconID) {
            return icon
        }
        if let iconID = pathMap[normalizedName], let icon = icon(id: iconID) {
            return icon
        }
        if isExpanded, let normalizedRelativePath, let iconID = fallbackMap[normalizedRelativePath], let icon = icon(id: iconID) {
            return icon
        }
        if isExpanded, let iconID = fallbackMap[normalizedName], let icon = icon(id: iconID) {
            return icon
        }
        return defaultFolderIcon(isExpanded: isExpanded, isRoot: isRoot)
    }

    func icon(id: String) -> FileIcon? {
        guard let iconPath = iconDefinitions[id]?.iconPath else { return nil }
        let fileName = (iconPath as NSString).lastPathComponent
        guard !fileName.isEmpty else { return nil }
        return FileIcon(id: id, relativePath: "icons/\(fileName)")
    }

    private func defaultFileIcon() -> FileIcon? {
        guard let defaultFileIconID else { return nil }
        return icon(id: defaultFileIconID)
    }

    private func defaultFolderIcon(isExpanded: Bool, isRoot: Bool) -> FileIcon? {
        let id = if isRoot {
            isExpanded ? defaultExpandedRootFolderIconID : defaultRootFolderIconID
        } else {
            isExpanded ? defaultExpandedFolderIconID : defaultFolderIconID
        }
        guard let id else { return nil }
        return icon(id: id)
    }

    private func folderMap(isExpanded: Bool, isRoot: Bool) -> [String: String] {
        if isRoot {
            return isExpanded ? rootFolderNamesExpanded : rootFolderNames
        }
        return isExpanded ? folderNamesExpanded : folderNames
    }

    private func extensionCandidates(for normalizedName: String) -> [String] {
        let pieces = normalizedName.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count > 1 else { return [] }

        var candidates: [String] = []
        candidates.reserveCapacity(pieces.count - 1)

        for index in 1 ..< pieces.count {
            let suffix = pieces[index...].joined(separator: ".")
            guard !suffix.isEmpty else { continue }
            candidates.append(suffix)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }
    }

    private static func normalizedMap(_ map: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in map {
            result[normalizePath(key) ?? normalizeKey(key)] = value
        }
        return result
    }

    private static func normalizePath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
