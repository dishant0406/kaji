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
        let local = localPath(remotePath: remotePath, subPath: subPath)
        return requiredFiles.contains { required in
            local == required || local.hasPrefix(required + "/")
        }
    }

    static func missingAuxiliaryFiles(from files: [SpeechModelRemoteFile], requiredFiles: [String]) -> [String] {
        let localPaths = Set(files.map(\.localPath))
        return requiredFiles.filter { file in
            !file.hasSuffix(".mlmodelc") && !file.hasSuffix(".mlpackage") && !localPaths.contains(file)
        }
    }
}
