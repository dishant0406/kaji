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
}
