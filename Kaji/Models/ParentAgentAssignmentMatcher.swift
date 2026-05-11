import Foundation

enum ParentAgentAssignmentMatcher {
    static func matches(task: String, assignment: ParentAgentAssignment) -> Bool {
        let taskTokens = tokens(task)
        guard !taskTokens.isEmpty else { return false }
        let assignmentTokens = tokens([assignment.title, assignment.prompt].joined(separator: " "))
        guard !assignmentTokens.isEmpty else { return false }
        if taskTokens.isSubset(of: assignmentTokens) || assignmentTokens.isSubset(of: taskTokens) { return true }
        let overlap = taskTokens.intersection(assignmentTokens)
        let threshold = min(2, min(taskTokens.count, assignmentTokens.count))
        return overlap.count >= threshold
    }

    static func tokens(_ text: String) -> Set<String> {
        let stopWords: Set = [
            "a", "an", "and", "app", "can", "code", "current", "for", "in", "is", "it", "new", "of", "on", "or", "so",
            "that", "the", "this", "to", "with", "needed", "need", "needs", "retry", "replace", "replacing", "attempt",
            "previous", "current", "complete", "finish", "fix", "update", "updating", "change", "changes",
        ]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(words.filter { $0.count > 2 && !stopWords.contains($0) })
    }
}
