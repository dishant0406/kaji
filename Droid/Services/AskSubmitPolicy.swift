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
             .taskAdd,
             .taskEdit,
             .taskDelete,
             .projectAdd,
             .attach,
             .execute,
             .executeAdd,
             .executeEdit,
             .executeDelete:
            false
        case .provider,
             .mode,
             .project,
             .worktree:
            false
        }
    }
}
