import Foundation

struct CodexSessionFileRecord: Equatable {
    let path: String
    let modifiedAt: Date
}

enum CodexSessionFileSelector {
    static func selectRecentPaths(from records: [CodexSessionFileRecord], limit: Int) -> [String] {
        records
            .sorted {
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                return $0.path < $1.path
            }
            .prefix(limit)
            .map(\.path)
    }
}

struct CodexSessionFileScanner {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func recentSessionFiles(rootURL: URL, limit: Int) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        else { return [] }

        let records = enumerator.compactMap { item -> CodexSessionFileRecord? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else {
                return nil
            }
            guard values.isRegularFile != false else { return nil }
            return CodexSessionFileRecord(
                path: url.path,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }

        return CodexSessionFileSelector
            .selectRecentPaths(from: records, limit: limit)
            .map { URL(fileURLWithPath: $0) }
    }
}
