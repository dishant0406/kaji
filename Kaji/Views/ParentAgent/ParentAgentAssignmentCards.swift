import SwiftUI

struct ParentAgentAssignmentGroup: View {
    let assignments: [ParentAgentAssignment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "workflow", size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
                Text("Assignments")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text("\(assignments.count)")
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fgDim)
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
                            .kajiFont(size: 12, weight: .semibold)
                            .foregroundStyle(KajiTheme.fg)
                            .lineLimit(1)
                        Text(status.rawValue)
                            .kajiFont(size: 11, weight: .medium)
                            .foregroundStyle(statusColor)
                    }
                    Text(metadata)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgMuted)
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
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KajiTheme.border.opacity(0.6), lineWidth: 1)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
    }

    private func assignmentBadge(_ text: String) -> some View {
        Text(text)
            .kajiFont(size: 10, weight: .medium)
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(KajiTheme.surface, in: Capsule())
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
            KajiTheme.diffAddFg
        case .running,
             .queued,
             .planned,
             .choosingAgent:
            KajiTheme.accent
        case .waitingForUser:
            KajiTheme.diffHunkFg
        case .blocked,
             .requiresIsolation:
            KajiTheme.diffHunkFg
        case .incomplete,
             .failed,
             .stopped,
             .stale:
            KajiTheme.diffRemoveFg
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
