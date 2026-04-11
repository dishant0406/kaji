import Foundation

final class GitRepositoryService: Sendable {
    struct PatchAndCompareResult {
        let rows: [DiffDisplayRow]
        let truncated: Bool
        let additions: Int
        let deletions: Int
    }

    enum GitError: LocalizedError {
        case notGitRepository
        case noUpstreamBranch
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notGitRepository:
                "This folder is not a Git repository."
            case .noUpstreamBranch:
                "The current branch has no upstream branch on the remote."
            case let .commandFailed(message):
                message
            }
        }
    }

    struct PRInfo: Equatable {
        let url: String
        let number: Int
        let state: PRState
        let isDraft: Bool
        let baseBranch: String
        let mergeable: Bool?
        let checks: PRChecks
    }

    enum PRState: String {
        case open = "OPEN"
        case closed = "CLOSED"
        case merged = "MERGED"
    }

    struct PRChecks: Equatable {
        let status: PRChecksStatus
        let passing: Int
        let failing: Int
        let pending: Int
        let total: Int
    }

    enum PRChecksStatus: Equatable {
        case none
        case pending
        case success
        case failure
    }

    struct AheadBehind: Equatable {
        let ahead: Int
        let behind: Int
        let hasUpstream: Bool
    }

    enum PRCreateError: LocalizedError {
        case ghNotInstalled
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .ghNotInstalled:
                "GitHub CLI (gh) is not installed. Install it with `brew install gh`."
            case let .commandFailed(message):
                message
            }
        }
    }

    enum PRMergeMethod {
        case merge
        case squash
        case rebase

        var ghFlag: String {
            switch self {
            case .merge: "--merge"
            case .squash: "--squash"
            case .rebase: "--rebase"
            }
        }
    }

    nonisolated func currentBranch(repoPath: String) async throws -> String {
        let result = try runGit(repoPath: repoPath, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        guard result.status == 0 else {
            throw GitError.commandFailed("Failed to get current branch.")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func isGhInstalled() async -> Bool {
        resolveExecutable("gh") != nil
    }

    nonisolated func pullRequestInfo(repoPath: String, branch: String) async -> PRInfo? {
        guard let ghPath = resolveExecutable("gh") else { return nil }
        let result = try? runCommand(
            executable: ghPath,
            arguments: [
                "pr", "view", branch,
                "--json", "url,number,state,isDraft,baseRefName,mergeable,statusCheckRollup",
            ],
            workingDirectory: repoPath
        )
        guard let result, result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let url = json["url"] as? String,
              let number = json["number"] as? Int,
              let stateRaw = json["state"] as? String
        else { return nil }

        let state = PRState(rawValue: stateRaw) ?? .open
        let isDraft = json["isDraft"] as? Bool ?? false
        let baseBranch = json["baseRefName"] as? String ?? ""
        let mergeableRaw = json["mergeable"] as? String
        let mergeable: Bool? = switch mergeableRaw {
        case "MERGEABLE": true
        case "CONFLICTING": false
        default: nil
        }

        let rollup = json["statusCheckRollup"] as? [[String: Any]] ?? []
        let checks = Self.parseStatusChecks(rollup)

        return PRInfo(
            url: url,
            number: number,
            state: state,
            isDraft: isDraft,
            baseBranch: baseBranch,
            mergeable: mergeable,
            checks: checks
        )
    }

    private static func parseStatusChecks(_ rollup: [[String: Any]]) -> PRChecks {
        if rollup.isEmpty {
            return PRChecks(status: .none, passing: 0, failing: 0, pending: 0, total: 0)
        }

        var passing = 0
        var failing = 0
        var pending = 0

        for entry in rollup {
            let typename = entry["__typename"] as? String ?? ""
            let outcome: String
            if typename == "CheckRun" {
                let status = (entry["status"] as? String ?? "").uppercased()
                let conclusion = (entry["conclusion"] as? String ?? "").uppercased()
                if status != "COMPLETED" {
                    outcome = "PENDING"
                } else {
                    outcome = conclusion
                }
            } else {
                outcome = (entry["state"] as? String ?? "").uppercased()
            }

            switch outcome {
            case "SUCCESS",
                 "NEUTRAL",
                 "SKIPPED":
                passing += 1
            case "FAILURE",
                 "ERROR",
                 "CANCELLED",
                 "TIMED_OUT",
                 "ACTION_REQUIRED",
                 "STARTUP_FAILURE":
                failing += 1
            case "PENDING",
                 "QUEUED",
                 "IN_PROGRESS",
                 "WAITING",
                 "REQUESTED",
                 "EXPECTED":
                pending += 1
            default:
                pending += 1
            }
        }

        let total = passing + failing + pending
        let status: PRChecksStatus = if failing > 0 {
            .failure
        } else if pending > 0 {
            .pending
        } else if passing > 0 {
            .success
        } else {
            .none
        }
        return PRChecks(status: status, passing: passing, failing: failing, pending: pending, total: total)
    }

    nonisolated func aheadBehind(repoPath: String, branch: String) async -> AheadBehind {
        let upstreamResult = try? runGit(
            repoPath: repoPath,
            arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"]
        )
        guard let upstreamResult, upstreamResult.status == 0 else {
            return AheadBehind(ahead: 0, behind: 0, hasUpstream: false)
        }

        let countsResult = try? runGit(
            repoPath: repoPath,
            arguments: ["rev-list", "--left-right", "--count", "\(branch)...\(branch)@{upstream}"]
        )
        guard let countsResult, countsResult.status == 0 else {
            return AheadBehind(ahead: 0, behind: 0, hasUpstream: true)
        }
        let parts = countsResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1])
        else {
            return AheadBehind(ahead: 0, behind: 0, hasUpstream: true)
        }
        return AheadBehind(ahead: ahead, behind: behind, hasUpstream: true)
    }

    func hasRemoteBranch(repoPath: String, branch: String) async -> Bool {
        let result = try? runGit(
            repoPath: repoPath,
            arguments: ["ls-remote", "--heads", "origin", branch]
        )
        guard let result, result.status == 0 else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func listRemoteBranches(repoPath: String) async throws -> [String] {
        let result = try runGit(
            repoPath: repoPath,
            arguments: [
                "for-each-ref",
                "--format=%(refname:short)",
                "refs/remotes/origin",
            ]
        )
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to list remote branches." : result.stderr)
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasSuffix("/HEAD") && $0.hasPrefix("origin/") }
            .map { String($0.dropFirst("origin/".count)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func lastCommitSubject(repoPath: String) async -> String? {
        let result = try? runGit(
            repoPath: repoPath,
            arguments: ["log", "-1", "--pretty=%s"]
        )
        guard let result, result.status == 0 else { return nil }
        let subject = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? nil : subject
    }

    func lastCommitBody(repoPath: String) async -> String? {
        let result = try? runGit(
            repoPath: repoPath,
            arguments: ["log", "-1", "--pretty=%b"]
        )
        guard let result, result.status == 0 else { return nil }
        let body = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    nonisolated func defaultBranch(repoPath: String) async -> String? {
        let symbolic = try? runGit(
            repoPath: repoPath,
            arguments: ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]
        )
        if let symbolic, symbolic.status == 0 {
            let value = symbolic.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("origin/") {
                return String(value.dropFirst("origin/".count))
            }
            if !value.isEmpty { return value }
        }

        if let ghPath = resolveExecutable("gh") {
            let result = try? runCommand(
                executable: ghPath,
                arguments: ["repo", "view", "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"],
                workingDirectory: repoPath
            )
            if let result, result.status == 0 {
                let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        return nil
    }

    func createPullRequest(
        repoPath: String,
        branch: String,
        baseBranch: String,
        title: String,
        body: String,
        draft: Bool = false
    ) async throws -> PRInfo {
        guard let ghPath = resolveExecutable("gh") else {
            throw PRCreateError.ghNotInstalled
        }

        var arguments: [String] = [
            "pr", "create",
            "--head", branch,
            "--base", baseBranch,
            "--title", title,
        ]
        arguments.append("--body")
        arguments.append(body)
        if draft {
            arguments.append("--draft")
        }

        let createResult = try runCommand(
            executable: ghPath,
            arguments: arguments,
            workingDirectory: repoPath
        )
        guard createResult.status == 0 else {
            let message = createResult.stderr.isEmpty ? createResult.stdout : createResult.stderr
            throw PRCreateError.commandFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Failed to create pull request."
                    : message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let info = await pullRequestInfo(repoPath: repoPath, branch: branch) {
            return info
        }

        let fallbackURL = createResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        throw PRCreateError.commandFailed(
            fallbackURL.isEmpty
                ? "Pull request created but could not be read back."
                : "Pull request created at \(fallbackURL) but could not be read back."
        )
    }

    func mergePullRequest(
        repoPath: String,
        number: Int,
        method: PRMergeMethod = .merge,
        deleteBranch: Bool = true
    ) async throws {
        guard let ghPath = resolveExecutable("gh") else {
            throw PRCreateError.ghNotInstalled
        }
        var arguments = ["pr", "merge", String(number), method.ghFlag]
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        let result = try runCommand(
            executable: ghPath,
            arguments: arguments,
            workingDirectory: repoPath
        )
        guard result.status == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw PRCreateError.commandFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Failed to merge pull request."
                    : message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func closePullRequest(repoPath: String, number: Int) async throws {
        guard let ghPath = resolveExecutable("gh") else {
            throw PRCreateError.ghNotInstalled
        }
        let result = try runCommand(
            executable: ghPath,
            arguments: ["pr", "close", String(number)],
            workingDirectory: repoPath
        )
        guard result.status == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw PRCreateError.commandFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Failed to close pull request."
                    : message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func changedFiles(repoPath: String, ignoreWhitespace: Bool = false) async throws -> [GitStatusFile] {
        let result = try runGit(repoPath: repoPath, arguments: ["rev-parse", "--is-inside-work-tree"])
        guard result.status == 0, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw GitError.notGitRepository
        }

        let statusResult = try runGit(
            repoPath: repoPath,
            arguments: ["-c", "core.quotepath=false", "status", "--porcelain=1", "-z", "--untracked-files=all"]
        )
        guard statusResult.status == 0 else {
            throw GitError.commandFailed(statusResult.stderr.isEmpty ? "Failed to load Git status." : statusResult.stderr)
        }

        let wsFlag = ignoreWhitespace ? ["-w"] : [String]()
        let numstatResult = try runGit(
            repoPath: repoPath,
            arguments: ["-c", "core.quotepath=false", "diff", "--numstat", "--no-color", "--no-ext-diff"] + wsFlag
        )
        let stats = GitStatusParser.parseNumstat(numstatResult.stdout)

        return GitStatusParser.parseStatusPorcelain(statusResult.stdoutData, stats: stats).map { file in
            guard file.additions == nil, file.xStatus == "?" || file.xStatus == "A" else { return file }
            let lineCount = Self.countLines(repoPath: repoPath, relativePath: file.path)
            return GitStatusFile(
                path: file.path,
                oldPath: file.oldPath,
                xStatus: file.xStatus,
                yStatus: file.yStatus,
                additions: lineCount,
                deletions: 0,
                isBinary: file.isBinary
            )
        }
    }

    private static func countLines(repoPath: String, relativePath: String) -> Int? {
        let fullPath = (repoPath as NSString).appendingPathComponent(relativePath)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return content.isEmpty ? 0 : content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    func patchAndCompare(
        repoPath: String,
        filePath: String,
        lineLimit: Int?,
        ignoreWhitespace: Bool = false
    ) async throws -> PatchAndCompareResult {
        let statusResult = try runGit(
            repoPath: repoPath,
            arguments: ["-c", "core.quotepath=false", "status", "--porcelain=1", "-z", "--", filePath]
        )
        let statusString = statusResult.stdout.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))

        if statusString.hasPrefix("??") || statusString.hasPrefix("A ") {
            return try untrackedOrNewFileDiff(repoPath: repoPath, filePath: filePath, lineLimit: lineLimit)
        }

        let wsFlag = ignoreWhitespace ? ["-w"] : [String]()

        let stagedResult = try runGit(
            repoPath: repoPath,
            arguments: ["-c", "core.quotepath=false", "diff", "--cached", "--no-color", "--no-ext-diff"] + wsFlag + ["--", filePath],
            lineLimit: lineLimit
        )
        guard stagedResult.status == 0 else {
            throw GitError.commandFailed(stagedResult.stderr.isEmpty ? "Failed to load diff for \(filePath)." : stagedResult.stderr)
        }

        let unstagedResult = try runGit(
            repoPath: repoPath,
            arguments: ["-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff"] + wsFlag + ["--", filePath],
            lineLimit: lineLimit
        )
        guard unstagedResult.status == 0 else {
            throw GitError.commandFailed(unstagedResult.stderr.isEmpty ? "Failed to load diff for \(filePath)." : unstagedResult.stderr)
        }

        let combinedPatch: String
        let combinedTruncated: Bool
        if !stagedResult.stdout.isEmpty, !unstagedResult.stdout.isEmpty {
            combinedPatch = stagedResult.stdout + "\n" + unstagedResult.stdout
            combinedTruncated = stagedResult.truncated || unstagedResult.truncated
        } else if !stagedResult.stdout.isEmpty {
            combinedPatch = stagedResult.stdout
            combinedTruncated = stagedResult.truncated
        } else {
            combinedPatch = unstagedResult.stdout
            combinedTruncated = unstagedResult.truncated
        }

        let parsed = GitDiffParser.parseRows(combinedPatch)
        return PatchAndCompareResult(
            rows: GitDiffParser.collapseContextRows(parsed.rows),
            truncated: combinedTruncated,
            additions: parsed.additions,
            deletions: parsed.deletions
        )
    }

    private func untrackedOrNewFileDiff(repoPath: String, filePath: String, lineLimit: Int?) throws -> PatchAndCompareResult {
        let fullPath = (repoPath as NSString).appendingPathComponent(filePath)
        let resolvedRepo = (repoPath as NSString).standardizingPath
        let resolvedFull = (fullPath as NSString).standardizingPath
        guard resolvedFull.hasPrefix(resolvedRepo + "/") else {
            throw GitError.commandFailed("File path is outside the repository.")
        }
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8)
        else {
            return PatchAndCompareResult(rows: [], truncated: false, additions: 0, deletions: 0)
        }

        let lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let effectiveLines = lineLimit.map { min(lines.count, $0) } ?? lines.count
        let truncated = lineLimit.map { lines.count > $0 } ?? false

        var rows: [DiffDisplayRow] = []
        rows.append(DiffDisplayRow(
            kind: .hunk,
            oldLineNumber: nil,
            newLineNumber: nil,
            oldText: nil,
            newText: nil,
            text: "@@ -0,0 +1,\(lines.count) @@ (new file)"
        ))

        for i in 0 ..< effectiveLines {
            let line = String(lines[i])
            rows.append(DiffDisplayRow(
                kind: .addition,
                oldLineNumber: nil,
                newLineNumber: i + 1,
                oldText: nil,
                newText: line,
                text: "+\(line)"
            ))
        }

        return PatchAndCompareResult(
            rows: GitDiffParser.collapseContextRows(rows),
            truncated: truncated,
            additions: effectiveLines,
            deletions: 0
        )
    }

    func stageFiles(repoPath: String, paths: [String]) async throws {
        for path in paths {
            try validatePath(repoPath: repoPath, relativePath: path)
        }
        let result = try runGit(repoPath: repoPath, arguments: ["add", "--"] + paths)
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to stage files." : result.stderr)
        }
    }

    func stageAll(repoPath: String) async throws {
        let result = try runGit(repoPath: repoPath, arguments: ["add", "-A"])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to stage all files." : result.stderr)
        }
    }

    func unstageFiles(repoPath: String, paths: [String]) async throws {
        for path in paths {
            try validatePath(repoPath: repoPath, relativePath: path)
        }
        let result = try runGit(repoPath: repoPath, arguments: ["reset", "HEAD", "--"] + paths)
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to unstage files." : result.stderr)
        }
    }

    func unstageAll(repoPath: String) async throws {
        let result = try runGit(repoPath: repoPath, arguments: ["reset", "HEAD"])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to unstage all files." : result.stderr)
        }
    }

    func discardFiles(repoPath: String, paths: [String], untrackedPaths: [String]) async throws {
        for path in paths + untrackedPaths {
            try validatePath(repoPath: repoPath, relativePath: path)
        }

        if !paths.isEmpty {
            let result = try runGit(repoPath: repoPath, arguments: ["checkout", "--"] + paths)
            guard result.status == 0 else {
                throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to discard changes." : result.stderr)
            }
        }

        for relativePath in untrackedPaths {
            let fullPath = (repoPath as NSString).appendingPathComponent(relativePath)
            try FileManager.default.removeItem(atPath: fullPath)
        }
    }

    func discardAll(repoPath: String) async throws {
        let checkoutResult = try runGit(repoPath: repoPath, arguments: ["checkout", "--", "."])
        guard checkoutResult.status == 0 else {
            throw GitError.commandFailed(
                checkoutResult.stderr.isEmpty ? "Failed to discard tracked changes." : checkoutResult.stderr
            )
        }

        let cleanResult = try runGit(repoPath: repoPath, arguments: ["clean", "-fd"])
        guard cleanResult.status == 0 else {
            throw GitError.commandFailed(
                cleanResult.stderr.isEmpty ? "Failed to clean untracked files." : cleanResult.stderr
            )
        }
    }

    func commit(repoPath: String, message: String) async throws -> String {
        let result = try runGit(repoPath: repoPath, arguments: ["commit", "-m", message])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to commit." : result.stderr)
        }

        let hashResult = try runGit(repoPath: repoPath, arguments: ["rev-parse", "--short", "HEAD"])
        guard hashResult.status == 0 else { return "" }
        return hashResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func push(repoPath: String) async throws {
        let result = try runGit(repoPath: repoPath, arguments: ["push"])
        guard result.status == 0 else {
            if result.stderr.contains("has no upstream branch") {
                throw GitError.noUpstreamBranch
            }
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to push." : result.stderr)
        }
    }

    func pushSetUpstream(repoPath: String, branch: String) async throws {
        let result = try runGit(repoPath: repoPath, arguments: ["push", "--set-upstream", "origin", branch])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to push." : result.stderr)
        }
    }

    func pull(repoPath: String) async throws {
        let result = try runGit(repoPath: repoPath, arguments: ["pull"])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to pull." : result.stderr)
        }
    }

    func localBranchExists(repoPath: String, name: String) async -> Bool {
        let result = try? runGit(
            repoPath: repoPath,
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(name)"]
        )
        return result?.status == 0
    }

    func listBranches(repoPath: String) async throws -> [String] {
        let result = try runGit(
            repoPath: repoPath,
            arguments: ["branch", "--list", "--format=%(refname:short)"]
        )
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to list branches." : result.stderr)
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static let allowedBranchCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._/-"))

    func switchBranch(repoPath: String, branch: String) async throws {
        guard !branch.isEmpty,
              branch.unicodeScalars.allSatisfy({ Self.allowedBranchCharacters.contains($0) })
        else {
            throw GitError.commandFailed("Invalid branch name.")
        }
        let result = try runGit(repoPath: repoPath, arguments: ["switch", branch])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to switch branch." : result.stderr)
        }
    }

    func createAndSwitchBranch(repoPath: String, name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.hasPrefix("-"),
              trimmedName.unicodeScalars.allSatisfy({ Self.allowedBranchCharacters.contains($0) })
        else {
            throw GitError.commandFailed("Invalid branch name.")
        }
        let result = try runGit(repoPath: repoPath, arguments: ["switch", "-c", trimmedName])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to create branch." : result.stderr)
        }
    }

    private static let commitFieldSeparator = "\u{1F}"
    private static let commitRecordSeparator = "\u{1E}"

    private static let logFormat = [
        "%H", "%h", "%s", "%an", "%aI", "%D", "%P",
    ].joined(separator: commitFieldSeparator) + commitRecordSeparator

    func commitLog(repoPath: String, maxCount: Int = 100, skip: Int = 0) async throws -> [GitCommit] {
        let result = try runGit(
            repoPath: repoPath,
            arguments: [
                "log",
                "--decorate=full",
                "--format=\(Self.logFormat)",
                "--max-count=\(maxCount)",
                "--skip=\(skip)",
            ]
        )
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to load commit history." : result.stderr)
        }
        return parseCommitLog(result.stdout)
    }

    private func parseCommitLog(_ raw: String) -> [GitCommit] {
        let records = raw.split(separator: Character(Self.commitRecordSeparator), omittingEmptySubsequences: true)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        return records.compactMap { record in
            let fields = record.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: Character(Self.commitFieldSeparator), maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count >= 7 else { return nil }

            let hash = String(fields[0])
            let shortHash = String(fields[1])
            let subject = String(fields[2])
            let authorName = String(fields[3])
            let dateString = String(fields[4])
            let refsRaw = String(fields[5])
            let parentsRaw = String(fields[6])

            let date = dateFormatter.date(from: dateString) ?? Date.distantPast
            let refs = Self.parseRefs(refsRaw)
            let parents = parentsRaw.split(separator: " ").map(String.init)

            return GitCommit(
                hash: hash,
                shortHash: shortHash,
                subject: subject,
                authorName: authorName,
                authorDate: date,
                refs: refs,
                parentHashes: parents
            )
        }
    }

    private static func parseRefs(_ raw: String) -> [GitRef] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { segment in
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            if trimmed == "HEAD" {
                return GitRef(name: "HEAD", kind: .head)
            }
            if trimmed.hasPrefix("HEAD -> ") {
                let branch = String(trimmed.dropFirst("HEAD -> ".count))
                    .replacingOccurrences(of: "refs/heads/", with: "")
                return GitRef(name: branch, kind: .localBranch)
            }
            if trimmed.hasPrefix("tag: ") {
                let tag = String(trimmed.dropFirst("tag: ".count))
                    .replacingOccurrences(of: "refs/tags/", with: "")
                return GitRef(name: tag, kind: .tag)
            }
            if trimmed.hasPrefix("refs/heads/") {
                let name = String(trimmed.dropFirst("refs/heads/".count))
                return GitRef(name: name, kind: .localBranch)
            }
            if trimmed.hasPrefix("refs/remotes/") {
                let name = String(trimmed.dropFirst("refs/remotes/".count))
                return GitRef(name: name, kind: .remoteBranch)
            }
            if trimmed.hasPrefix("refs/tags/") {
                let name = String(trimmed.dropFirst("refs/tags/".count))
                return GitRef(name: name, kind: .tag)
            }
            return GitRef(name: trimmed, kind: .localBranch)
        }
    }

    func cherryPick(repoPath: String, hash: String) async throws {
        try validateHash(hash)
        let result = try runGit(repoPath: repoPath, arguments: ["cherry-pick", hash])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to cherry-pick." : result.stderr)
        }
    }

    func createBranch(repoPath: String, name: String, startPoint: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.hasPrefix("-"),
              trimmedName.unicodeScalars.allSatisfy({ Self.allowedBranchCharacters.contains($0) })
        else {
            throw GitError.commandFailed("Invalid branch name.")
        }
        try validateHash(startPoint)
        let result = try runGit(repoPath: repoPath, arguments: ["branch", "--", trimmedName, startPoint])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to create branch." : result.stderr)
        }
    }

    private static let allowedTagCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._/-"))

    func createTag(repoPath: String, name: String, hash: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.hasPrefix("-"),
              trimmedName.unicodeScalars.allSatisfy({ Self.allowedTagCharacters.contains($0) })
        else {
            throw GitError.commandFailed("Invalid tag name.")
        }
        try validateHash(hash)
        let result = try runGit(repoPath: repoPath, arguments: ["tag", "--", trimmedName, hash])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to create tag." : result.stderr)
        }
    }

    func checkoutDetached(repoPath: String, hash: String) async throws {
        try validateHash(hash)
        let result = try runGit(repoPath: repoPath, arguments: ["checkout", "--detach", hash])
        guard result.status == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? "Failed to checkout." : result.stderr)
        }
    }

    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    private func validateHash(_ hash: String) throws {
        guard !hash.isEmpty,
              hash.count <= 40,
              hash.unicodeScalars.allSatisfy({ Self.hexCharacters.contains($0) })
        else {
            throw GitError.commandFailed("Invalid commit hash.")
        }
    }

    private func validatePath(repoPath: String, relativePath: String) throws {
        let fullPath = (repoPath as NSString).appendingPathComponent(relativePath)
        let resolvedRepo = (repoPath as NSString).standardizingPath
        let resolvedFull = (fullPath as NSString).standardizingPath
        guard resolvedFull.hasPrefix(resolvedRepo + "/") else {
            throw GitError.commandFailed("File path is outside the repository.")
        }
    }

    private struct GitRunResult {
        let status: Int32
        let stdout: String
        let stdoutData: Data
        let stderr: String
        let truncated: Bool
    }

    nonisolated private func runGit(repoPath: String, arguments: [String], lineLimit: Int? = nil) throws -> GitRunResult {
        let args = ["git", "-C", repoPath] + arguments
        return try runGitSync(arguments: args, lineLimit: lineLimit)
    }

    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    nonisolated private func resolveExecutable(_ name: String) -> String? {
        for directory in Self.searchPaths {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    nonisolated private func runCommand(
        executable: String,
        arguments: [String],
        workingDirectory: String
    ) throws -> GitRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return GitRunResult(status: process.terminationStatus, stdout: stdout, stdoutData: stdoutData, stderr: stderr, truncated: false)
    }

    nonisolated private func runGitSync(arguments: [String], lineLimit: Int?) throws -> GitRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData: Data = if let lineLimit {
            try readWithLineLimit(handle: stdoutPipe.fileHandleForReading, process: process, lineLimit: lineLimit)
        } else {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let truncated = process.terminationReason == .uncaughtSignal
        return GitRunResult(status: process.terminationStatus, stdout: stdout, stdoutData: stdoutData, stderr: stderr, truncated: truncated)
    }

    nonisolated private func readWithLineLimit(handle: FileHandle, process: Process, lineLimit: Int) throws -> Data {
        var collected = Data()
        var currentLineCount = 0
        let chunkSize = 65536

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                return collected
            }

            collected.append(chunk)
            currentLineCount += chunk.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }

            if currentLineCount >= lineLimit {
                process.terminate()
                return collected
            }
        }
    }
}
