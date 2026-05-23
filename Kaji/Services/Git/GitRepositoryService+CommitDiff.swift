import Foundation

extension GitRepositoryService {
    func commitFiles(repoPath: String, hash: String, parentHash: String?) async throws -> [GitStatusFile] {
        try Self.validateCommitHash(hash)
        if let parentHash {
            try Self.validateCommitHash(parentHash)
        }
        let base = parentHash ?? Self.emptyTreeHash
        async let namesTask = GitProcessRunner.runGit(
            repoPath: repoPath,
            arguments: ["diff", "--name-status", "--no-renames", base, hash]
        )
        async let statsTask = GitProcessRunner.runGit(
            repoPath: repoPath,
            arguments: ["diff", "--numstat", "--no-renames", base, hash]
        )
        let namesResult = try await namesTask
        let statsResult = try await statsTask
        guard namesResult.status == 0 else {
            throw GitError.commandFailed(namesResult.stderr.isEmpty ? "Failed to load commit files." : namesResult.stderr)
        }
        let stats = statsResult.status == 0 ? Self.numstatByPath(statsResult.stdout) : [:]
        return namesResult.stdout.split(separator: "\n").compactMap { line in
            let columns = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 2, let status = columns[0].first else { return nil }
            let stat = stats[columns[1]]
            return GitStatusFile(
                path: columns[1],
                oldPath: nil,
                xStatus: status,
                yStatus: " ",
                additions: stat?.additions,
                deletions: stat?.deletions,
                isBinary: stat?.isBinary ?? false
            )
        }
    }

    func commitPatchAndCompare(
        repoPath: String,
        filePath: String,
        source: GitDiffSource,
        lineLimit: Int?,
        contextLineCount: Int
    ) async throws -> PatchAndCompareResult {
        guard case let .commit(hash, parentHash) = source else {
            return try await patchAndCompare(
                repoPath: repoPath,
                filePath: filePath,
                lineLimit: lineLimit,
                contextLineCount: contextLineCount
            )
        }
        try Self.validateCommitHash(hash)
        if let parentHash {
            try Self.validateCommitHash(parentHash)
        }
        let base = parentHash ?? Self.emptyTreeHash
        let result = try await GitProcessRunner.runGit(
            repoPath: repoPath,
            arguments: [
                "diff",
                "--unified=\(max(contextLineCount, 0))",
                "--no-color",
                "--no-ext-diff",
                base,
                hash,
                "--",
                filePath,
            ],
            lineLimit: lineLimit
        )
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to load commit diff." : result.stderr)
        }
        return await GitProcessRunner.offMain {
            let parsed = SwiftyDiffAdapter.parseRows(result.stdout)
            return PatchAndCompareResult(
                rows: parsed.rows,
                truncated: result.truncated,
                additions: parsed.additions,
                deletions: parsed.deletions
            )
        }
    }

    private static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    private static func validateCommitHash(_ hash: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hash.count >= 7, hash.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw GitError.commandFailed("Invalid commit hash.")
        }
    }

    private static func numstatByPath(_ raw: String) -> [String: NumstatEntry] {
        raw.split(separator: "\n").reduce(into: [:]) { result, line in
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 3 else { return }
            let binary = columns[0] == "-" || columns[1] == "-"
            result[columns[2]] = NumstatEntry(
                additions: binary ? nil : Int(columns[0]),
                deletions: binary ? nil : Int(columns[1]),
                isBinary: binary
            )
        }
    }
}
