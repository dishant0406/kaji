import ClosedLidCore
import Foundation
import Testing

@testable import Kaji

struct ClosedLidCompatibilityTestPolicyTests {
    @Test
    func continuousExternalHeartbeatsAndNoSleepLogPass() {
        let evidence = ClosedLidCompatibilityTestEvidence(
            samples: samples(gaps: [5, 5, 5]),
            pmsetBaseline: "baseline\n",
            pmsetAfterTest: "baseline\nDarkWake maintenance\n"
        )

        let result = ClosedLidCompatibilityTestPolicy.evaluate(evidence)

        #expect(result.succeeded)
        #expect(result.detail.contains("verified"))
    }

    @Test
    func heartbeatGapFailsEvenWhenFinalHeartbeatExists() {
        let evidence = ClosedLidCompatibilityTestEvidence(
            samples: samples(gaps: [5, 14, 5]),
            pmsetBaseline: "baseline\n",
            pmsetAfterTest: "baseline\n"
        )

        let result = ClosedLidCompatibilityTestPolicy.evaluate(evidence)

        #expect(!result.succeeded)
        #expect(result.detail.contains("paused"))
    }

    @Test
    func sleepLogEvidenceFailsAttestation() {
        let evidence = ClosedLidCompatibilityTestEvidence(
            samples: samples(gaps: [5, 5, 5]),
            pmsetBaseline: "baseline\n",
            pmsetAfterTest: "baseline\nEntering Sleep state due to 'Clamshell Sleep'\n"
        )

        let result = ClosedLidCompatibilityTestPolicy.evaluate(evidence)

        #expect(!result.succeeded)
        #expect(result.detail.contains("recorded sleep"))
    }

    @Test
    func replacedOrTruncatedSleepLogFailsClosed() {
        let evidence = ClosedLidCompatibilityTestEvidence(
            samples: samples(gaps: [5, 5, 5]),
            pmsetBaseline: "old baseline\n",
            pmsetAfterTest: "new log\n"
        )

        #expect(!ClosedLidCompatibilityTestPolicy.evaluate(evidence).succeeded)
    }

    @Test
    func differentSessionTokensNeverProduceAttestation() {
        var values = samples(gaps: [5, 5, 5])
        values[values.count - 1] = ClosedLidStandardSessionEvidence(
            sessionID: UUID(),
            armedMonotonicNanoseconds: values[0].armedMonotonicNanoseconds,
            lastHeartbeatMonotonicNanoseconds: values.last?.lastHeartbeatMonotonicNanoseconds ?? 0,
            heartbeatCount: values.last?.heartbeatCount ?? 0
        )
        let evidence = ClosedLidCompatibilityTestEvidence(
            samples: values,
            pmsetBaseline: "baseline\n",
            pmsetAfterTest: "baseline\n"
        )

        #expect(!ClosedLidCompatibilityTestPolicy.evaluate(evidence).succeeded)
    }

    private func samples(gaps: [UInt64]) -> [ClosedLidStandardSessionEvidence] {
        let sessionID = UUID()
        let armed: UInt64 = 1_000_000_000
        var timestamp = armed
        return gaps.enumerated().map { index, seconds in
            timestamp += seconds * 1_000_000_000
            return ClosedLidStandardSessionEvidence(
                sessionID: sessionID,
                armedMonotonicNanoseconds: armed,
                lastHeartbeatMonotonicNanoseconds: timestamp,
                heartbeatCount: UInt64(index + 1)
            )
        }
    }
}
