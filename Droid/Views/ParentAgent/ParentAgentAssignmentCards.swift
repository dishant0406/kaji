import SwiftUI

struct ParentAgentAssignmentGroup: View {
    let assignments: [ParentAgentAssignment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DroidIcon(systemName: "workflow", size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
                Text("Assignments")
                    .droidFont(size: 12, weight: .semibold)
                    .foregroundStyle(DroidTheme.fgMuted)
                Text("\(assignments.count)")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            ForEach(assignments) { assignment in
                ParentAgentAssignmentCard(assignment: assignment)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ParentAgentAssignmentCard: View {
    let assignment: ParentAgentAssignment
    @State private var runStore = AgentRunStore.shared
    @State private var feedStore = ChildAgentFeedStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                statusDot
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(assignment.title)
                            .droidFont(size: 12, weight: .semibold)
                            .foregroundStyle(DroidTheme.fg)
                            .lineLimit(1)
                        Text(status.rawValue)
                            .droidFont(size: 11, weight: .medium)
                            .foregroundStyle(statusColor)
                    }
                    Text(metadata)
                        .droidFont(size: 11)
                        .foregroundStyle(DroidTheme.fgDim)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .droidFont(size: 11)
                            .foregroundStyle(DroidTheme.fgMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if !changedFiles.isEmpty || verificationText != nil {
                HStack(spacing: 8) {
                    if !changedFiles.isEmpty {
                        assignmentBadge("\(changedFiles.count) files")
                    }
                    if assignment.attention != nil {
                        assignmentBadge("needs attention")
                    }
                    if let verificationText {
                        assignmentBadge(verificationText)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DroidTheme.border.opacity(0.6), lineWidth: 1)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
    }

    private func assignmentBadge(_ text: String) -> some View {
        Text(text)
            .droidFont(size: 10, weight: .medium)
            .foregroundStyle(DroidTheme.fgMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DroidTheme.surface, in: Capsule())
    }

    private var run: AgentRun? {
        assignment.runID.flatMap { runStore.run(id: $0) }
    }

    private var status: ParentAgentAssignmentStatus {
        guard assignment.status != .stopped else { return .stopped }
        switch run?.status {
        case .running:
            return .running
        case .waiting,
             .needsAttention:
            return .waitingForUser
        case .completed:
            return hasEvidence ? .completed : .incomplete
        case .failed:
            return .failed
        case .stale:
            return .stale
        case nil:
            return assignment.runID == nil ? assignment.status : .stale
        }
    }

    private var hasEvidence: Bool {
        assignment.finalSummary?.isEmpty == false ||
            assignment.runID.flatMap { feedStore.finalAnswer(runID: $0) } != nil ||
            !changedFiles.isEmpty
    }

    private var statusColor: Color {
        switch status {
        case .completed:
            DroidTheme.diffAddFg
        case .running,
             .queued,
             .planned,
             .choosingAgent:
            DroidTheme.accent
        case .waitingForUser:
            DroidTheme.diffHunkFg
        case .blocked,
             .requiresIsolation:
            DroidTheme.diffHunkFg
        case .incomplete,
             .failed,
             .stopped,
             .stale:
            DroidTheme.diffRemoveFg
        }
    }

    private var metadata: String {
        [providerText, assignment.worktreeName, runSuffix]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " - ")
    }

    private var providerText: String? {
        guard let providerID = assignment.providerID else { return nil }
        let provider = AgentMissionControlSnapshotBuilder.providerName(for: providerID)
        if let modelID = assignment.modelID { return "\(provider) / \(modelID)" }
        return provider
    }

    private var runSuffix: String? {
        assignment.runID.map { "run \(String($0.uuidString.prefix(8)))" }
    }

    private var detail: String? {
        assignment.attention.map { "\($0.title): \($0.detail)" } ??
            assignment.finalSummary ??
            assignment.runID.flatMap { feedStore.finalAnswer(runID: $0) } ??
            assignment.lastEvent ??
            run?.events.last?.text
    }

    private var changedFiles: [ParentAgentChangedFileContext] {
        if let run, !run.changedFiles.isEmpty {
            return run.changedFiles.map { file in
                ParentAgentChangedFileContext(
                    path: file.path,
                    oldPath: file.oldPath,
                    status: file.status.rawValue,
                    additions: file.additions,
                    deletions: file.deletions,
                    isBinary: file.isBinary
                )
            }
        }
        return assignment.changedFiles
    }

    private var verificationText: String? {
        let status = run?.verification.status.rawValue ?? assignment.verification?.status
        guard let status, status != AgentVerificationStatus.notStarted.rawValue else { return nil }
        return "verification \(status)"
    }
}
