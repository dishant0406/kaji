import ClosedLidCore
import Testing

@testable import Kaji

struct ClosedLidPresentationTests {
    @Test
    func everySessionStatusHasASafeAction() {
        let statuses: [ClosedLidSessionStatus] = [
            .unavailable,
            .off,
            .arming,
            .activeStandard,
            .activePowerProtect,
            .restoring,
            .safetyStopped(.thermalPressure),
            .failed("Restore verification failed"),
        ]

        for status in statuses {
            let presentation = ClosedLidStatusPresentation.resolve(status)
            #expect(presentation.canStart || presentation.canRestore || status == .unavailable)
            #expect(!presentation.detail.isEmpty)
            #expect(!presentation.annotation.isEmpty)
        }
    }

    @Test
    @MainActor
    func activePaletteOnlyOffersRestore() {
        for status in [ClosedLidSessionStatus.activeStandard, .activePowerProtect, .arming, .restoring] {
            let entries = AskPaletteEntries.build(context(status: status))

            #expect(entries.count == 1)
            #expect(entries.first?.action == .stopClosedLid)
        }
    }

    @Test
    @MainActor
    func failedPaletteOffersRestoreAndReprobe() {
        let entries = AskPaletteEntries.build(context(status: .failed("Live verification failed")))

        #expect(entries.map(\.action) == [.stopClosedLid, .probeClosedLid])
    }

    private func context(status: ClosedLidSessionStatus) -> AskPaletteContext {
        .init(
            fieldText: "/lid",
            prompt: "",
            projects: [],
            worktrees: [],
            provider: .terminal,
            sessionMode: .bestMatch,
            sessions: [],
            historyOptions: [],
            skillOptions: [],
            projectName: "muxy",
            worktreeName: "main",
            closedLidStatus: status,
            standardCompatibility: .verified,
            standardModeAvailable: true,
            powerProtectReady: true,
            powerProtectStatus: "helper ready"
        )
    }
}
