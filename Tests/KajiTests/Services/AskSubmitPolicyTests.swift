import Testing

@testable import Kaji

struct AskSubmitPolicyTests {
    @Test
    func sendsWhenAnnotationApplyLeavesNoActiveAnnotation() {
        #expect(AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .provider,
            updatedFieldText: "what is this :t:codex",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func sendsWhenAnnotationApplyChangesFieldButResolvesIt() {
        #expect(AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .provider,
            updatedFieldText: "what is this :t:codex",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func doesNotSendWhenAnnotationStillNeedsResolution() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .worktree,
            updatedFieldText: "what is this :wt:ma",
            canSend: true,
            hasActiveAnnotation: true
        ))
    }

    @Test
    func doesNotSendWhenPromptCannotBeSent() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .provider,
            updatedFieldText: "what is this :t:codex",
            canSend: false,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func doesNotSendImmediatelyAfterHistorySelection() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .history,
            updatedFieldText: ":t:codex :h:session-1",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func doesNotSendImmediatelyAfterSkillSelection() {
        #expect(!AskSubmitPolicy.shouldSendAfterAnnotationApply(
            appliedKey: .skill,
            updatedFieldText: ":t:codex :s:copywriting",
            canSend: true,
            hasActiveAnnotation: false
        ))
    }

    @Test
    func bookmarkAnnotationAppliesHighlightedEntry() {
        #expect(AskSubmitPolicy.shouldApplyHighlightedEntry(key: .bookmark))
    }

    @Test
    func historyAnnotationDoesNotApplyHighlightedEntry() {
        #expect(!AskSubmitPolicy.shouldApplyHighlightedEntry(key: .history))
    }

    @Test
    func resolvedHistoryAnnotationCanSubmitOnNextEnter() {
        #expect(AskSubmitPolicy.activeAnnotationIsResolved(
            key: .history,
            hasHistory: true,
            hasSkill: false
        ))
    }

    @Test
    func unresolvedHistoryAnnotationKeepsApplyingOptions() {
        #expect(!AskSubmitPolicy.activeAnnotationIsResolved(
            key: .history,
            hasHistory: false,
            hasSkill: false
        ))
    }
}
