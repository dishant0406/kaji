import Foundation

enum AskSubmitPolicy {
    static func shouldSendAfterAnnotationApply(
        appliedKey: AskAnnotationKey,
        updatedFieldText: String,
        canSend: Bool,
        hasActiveAnnotation: Bool
    ) -> Bool {
        if appliedKey == .history || appliedKey == .skill { return false }
        return canSend && !hasActiveAnnotation
    }

    static func shouldApplyHighlightedEntry(key: AskAnnotationKey) -> Bool {
        switch key {
        case .bookmark,
             .diff:
            true
        case .project,
             .worktree,
             .provider,
             .mode,
             .history,
             .skill,
             .task,
             .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .attach,
             .execute,
             .executeAdd,
             .executeEdit,
             .executeDelete,
             .bookmarkFolder:
            false
        }
    }

    static func activeAnnotationIsResolved(
        key: AskAnnotationKey,
        hasHistory: Bool,
        hasSkill: Bool
    ) -> Bool {
        switch key {
        case .history:
            hasHistory
        case .skill:
            hasSkill
        case .task,
             .diff,
             .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .attach,
             .execute,
             .executeAdd,
             .executeEdit,
             .executeDelete,
             .bookmark,
             .bookmarkFolder:
            false
        case .provider,
             .mode,
             .project,
             .worktree:
            false
        }
    }
}
