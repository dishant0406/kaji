import Foundation

struct ParentAgentSubagentRequest {
    let prompt: String
    let projectID: UUID
    let worktreeID: UUID
    let isolation: ParentAgentAssignmentIsolation
}

enum ParentAgentSubagentPolicyDecision: Equatable {
    case allowed
    case blocked(String, assignmentID: UUID?)
    case requiresIsolation(String, assignmentID: UUID?)
}

enum ParentAgentSubagentPolicy {
    static func decideSpawn(
        request: ParentAgentSubagentRequest,
        assignments: [ParentAgentAssignment]
    ) -> ParentAgentSubagentPolicyDecision {
        let active = assignments.filter { isActive($0.status) }
        if let duplicate = active.first(where: { ParentAgentAssignmentMatcher.matches(task: request.prompt, assignment: $0) }) {
            return .blocked("A subagent assignment is already working on this same task.", assignmentID: duplicate.id)
        }

        guard request.isolation == .sharedWorktree,
              expectsMutation(request.prompt)
        else { return .allowed }

        if let conflicting = active.first(where: { assignment in
            assignment.projectID == request.projectID &&
                assignment.worktreeID == request.worktreeID &&
                assignment.isolation == .sharedWorktree &&
                expectsMutation(assignment.prompt)
        }) {
            return .requiresIsolation(
                "Another write-capable subagent is active in this worktree. Use isolatedWorktree or wait for it to finish.",
                assignmentID: conflicting.id
            )
        }

        return .allowed
    }

    static func expectsMutation(_ prompt: String) -> Bool {
        let value = prompt.lowercased()
        let noEditMarkers = ["do not edit", "don't edit", "read only", "read-only", "review only"]
        if noEditMarkers.contains(where: value.contains) {
            return false
        }
        let mutationMarkers = [
            "fix",
            "implement",
            "edit",
            "modify",
            "patch",
            "refactor",
            "update",
            "add",
            "remove",
            "replace",
            "create",
            "delete",
        ]
        return mutationMarkers.contains { value.contains($0) }
    }

    private static func isActive(_ status: ParentAgentAssignmentStatus) -> Bool {
        status == .running || status == .waitingForUser || status == .queued || status == .planned || status == .choosingAgent
    }
}
