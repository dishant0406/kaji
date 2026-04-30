import Testing

@testable import Droid

struct AskSubmitPolicyTests {
    @Test
    func sendsWhenAnnotationApplyLeavesNoActiveAnnotation() {
        #expect(AskSubmitPolicy.shouldSendAfterAnnotationApply(
            updatedFieldText: "what is this :t:codex",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func sendsWhenAnnotationApplyChangesFieldButResolvesIt() {
        #expect(AskSubmitPolicy.shouldSendAfterAnnotationApply(
            updatedFieldText: "what is this :t:codex",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func doesNotSendWhenAnnotationStillNeedsResolution() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            updatedFieldText: "what is this :wt:ma",
            canSend: true,
            hasActiveAnnotation: true
        ))
    }

    @Test
    func doesNotSendWhenPromptCannotBeSent() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            updatedFieldText: "what is this :t:codex",
            canSend: false,
            hasActiveAnnotation: false
        ))
    }
}
