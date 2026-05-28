import Testing

@testable import Kaji

struct CodingAgentProcessKillPolicyTests {
    @Test
    func rejectsUnsafePIDs() {
        #expect(CodingAgentProcessKillPolicy.validate(pid: 0, currentPID: 10, parentPID: 9) == .invalidPID)
        #expect(CodingAgentProcessKillPolicy.validate(pid: 1, currentPID: 10, parentPID: 9) == .systemProcess)
        #expect(CodingAgentProcessKillPolicy.validate(pid: 10, currentPID: 10, parentPID: 9) == .currentProcess)
        #expect(CodingAgentProcessKillPolicy.validate(pid: 9, currentPID: 10, parentPID: 9) == .parentProcess)
    }

    @Test
    func allowsOtherPositivePIDs() {
        #expect(CodingAgentProcessKillPolicy.validate(pid: 42, currentPID: 10, parentPID: 9) == nil)
    }
}
