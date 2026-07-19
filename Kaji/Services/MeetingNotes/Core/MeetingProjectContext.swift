import Foundation

struct MeetingProjectContextInput {
    let projectID: UUID
    let name: String
    let summary: String
    let recentRelativeFilePaths: [String]
}

struct MeetingProjectContext: Codable, Equatable {
    struct Project: Codable, Equatable {
        let projectID: UUID
        let name: String
        let summary: String
        let recentRelativeFilePaths: [String]
    }

    let projects: [Project]
    let totalCharacterCount: Int
}

struct MeetingProjectContextLimits {
    var maximumProjects = 8
    var maximumFilesPerProject = 40
    var maximumTotalCharacters = 20000
    var maximumNameLength = 120
    var maximumSummaryLength = 2000
    var maximumRelativePathLength = 500
}

struct MeetingProjectContextBuilder {
    let limits: MeetingProjectContextLimits

    init(limits: MeetingProjectContextLimits = MeetingProjectContextLimits()) {
        self.limits = limits
    }

    func build(from inputs: [MeetingProjectContextInput], allowedProjectIDs: Set<UUID>) -> MeetingProjectContext {
        var remaining = limits.maximumTotalCharacters
        var seen = Set<UUID>()
        var projects: [MeetingProjectContext.Project] = []
        for input in inputs {
            guard projects.count < limits.maximumProjects,
                  allowedProjectIDs.contains(input.projectID),
                  seen.insert(input.projectID).inserted,
                  remaining > 0
            else {
                continue
            }
            let name = bounded(input.name, maximum: min(limits.maximumNameLength, remaining))
            guard !name.isEmpty else { continue }
            remaining -= name.count
            let summary = bounded(input.summary, maximum: min(limits.maximumSummaryLength, remaining))
            remaining -= summary.count
            var paths: [String] = []
            var seenPaths = Set<String>()
            for path in input.recentRelativeFilePaths {
                guard paths.count < limits.maximumFilesPerProject,
                      remaining > 0,
                      isSafeRelativePath(path)
                else {
                    continue
                }
                let boundedPath = bounded(path, maximum: min(limits.maximumRelativePathLength, remaining))
                guard !boundedPath.isEmpty, seenPaths.insert(boundedPath).inserted else { continue }
                paths.append(boundedPath)
                remaining -= boundedPath.count
            }
            projects.append(.init(
                projectID: input.projectID,
                name: name,
                summary: summary,
                recentRelativeFilePaths: paths
            ))
        }
        return MeetingProjectContext(
            projects: projects,
            totalCharacterCount: limits.maximumTotalCharacters - remaining
        )
    }

    private func bounded(_ value: String, maximum: Int) -> String {
        guard maximum > 0 else { return "" }
        let sanitized = value.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sanitized.prefix(maximum))
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        else {
            return false
        }
        return true
    }
}
