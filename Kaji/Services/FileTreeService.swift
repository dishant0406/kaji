import Foundation

struct FileTreeEntry: Hashable {
    let name: String
    let absolutePath: String
    let relativePath: String
    let isDirectory: Bool
    let isIgnored: Bool
}

enum FileTreeService {
    static func loadChildren(of directoryAbsolutePath: String, repoRoot: String) async -> [FileTreeEntry] {
        await GitProcessRunner.offMain {
            loadChildrenSync(of: directoryAbsolutePath, repoRoot: repoRoot)
        }
    }

    private static func loadChildrenSync(of directoryAbsolutePath: String, repoRoot: String) -> [FileTreeEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directoryAbsolutePath) else {
            return []
        }

        let classification = classifyNames(in: directoryAbsolutePath, repoRoot: repoRoot, candidates: contents)
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot

        var entries: [FileTreeEntry] = []
        entries.reserveCapacity(classification.visible.count)

        for name in classification.visible {
            if name == "." || name == ".." {
                continue
            }
            let absolute = directoryAbsolutePath.hasSuffix("/")
                ? directoryAbsolutePath + name
                : directoryAbsolutePath + "/" + name

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: absolute, isDirectory: &isDir) else { continue }

            let relative: String = if absolute.hasPrefix(normalizedRoot + "/") {
                String(absolute.dropFirst(normalizedRoot.count + 1))
            } else {
                name
            }

            entries.append(FileTreeEntry(
                name: name,
                absolutePath: absolute,
                relativePath: relative,
                isDirectory: isDir.boolValue,
                isIgnored: classification.ignored.contains(name)
            ))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return entries
    }

    private struct NameClassification {
        let visible: [String]
        let ignored: Set<String>
    }

    private static func classifyNames(
        in directoryAbsolutePath: String,
        repoRoot: String,
        candidates: [String]
    ) -> NameClassification {
        let isRepoChild = isInsideRepo(path: directoryAbsolutePath, repoRoot: repoRoot)
        guard isRepoChild else {
            return NameClassification(visible: candidates, ignored: [])
        }

        let ignored = ignoredNames(directoryAbsolutePath: directoryAbsolutePath, repoRoot: repoRoot, candidates: candidates)
        let visible = candidates.filter { $0 != ".git" }
        return NameClassification(visible: visible, ignored: ignored)
    }

    private static func isInsideRepo(path: String, repoRoot: String) -> Bool {
        let normalizedRoot = repoRoot.hasSuffix("/") ? String(repoRoot.dropLast()) : repoRoot
        return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
    }

    private static func ignoredNames(
        directoryAbsolutePath: String,
        repoRoot: String,
        candidates: [String]
    ) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let paths = candidates.map { name in
            directoryAbsolutePath.hasSuffix("/") ? directoryAbsolutePath + name : directoryAbsolutePath + "/" + name
        }
        let ignoredPaths = WorkspaceIgnoreClassifier().ignoredPaths(repoPath: repoRoot, paths: paths)
        return Set(candidates.filter { name in
            let path = directoryAbsolutePath.hasSuffix("/") ? directoryAbsolutePath + name : directoryAbsolutePath + "/" + name
            return ignoredPaths.contains(path)
        })
    }
}
