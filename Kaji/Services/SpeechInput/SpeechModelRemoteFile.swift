import Foundation

struct SpeechModelRemoteFile: Equatable, Hashable {
    let remotePath: String
    let localPath: String
    let size: Int64
}

struct SpeechModelTreeItem: Decodable {
    let path: String
    let type: String
    let size: Int?
}

enum SpeechModelRemoteFileMapper {
    static func localPath(remotePath: String, subPath: String?) -> String {
        guard let subPath, remotePath.hasPrefix(subPath + "/") else { return remotePath }
        return String(remotePath.dropFirst(subPath.count + 1))
    }

    static func shouldInclude(remotePath: String, subPath: String?, requiredFiles: [String]) -> Bool {
        guard isSafePath(remotePath) else { return false }
        let local = localPath(remotePath: remotePath, subPath: subPath)
        guard isSafePath(local) else { return false }
        return requiredFiles.contains { required in
            local == required || local.hasPrefix(required + "/")
        }
    }

    static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0")
        else {
            return false
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func missingAuxiliaryFiles(from files: [SpeechModelRemoteFile], requiredFiles: [String]) -> [String] {
        let localPaths = Set(files.map(\.localPath))
        return requiredFiles.filter { file in
            !file.hasSuffix(".mlmodelc") && !file.hasSuffix(".mlpackage") && !localPaths.contains(file)
        }
    }
}
