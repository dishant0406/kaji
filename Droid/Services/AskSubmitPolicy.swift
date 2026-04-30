import Foundation

enum AskSubmitPolicy {
    static func shouldSendAfterAnnotationApply(
        updatedFieldText: String,
        canSend: Bool,
        hasActiveAnnotation: Bool
    ) -> Bool {
        canSend && !hasActiveAnnotation
    }
}
