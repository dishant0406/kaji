import Testing

@testable import Kaji

struct PortKillPolicyTests {
    @Test
    func rejectsInvalidPID() {
        #expect(PortKillPolicy.validate(pid: 0, currentPID: 10, parentPID: 9) == .invalidPID)
        #expect(PortKillPolicy.validate(pid: -1, currentPID: 10, parentPID: 9) == .invalidPID)
    }

    @Test
    func rejectsCurrentAndParentProcesses() {
        #expect(PortKillPolicy.validate(pid: 10, currentPID: 10, parentPID: 9) == .currentProcess)
        #expect(PortKillPolicy.validate(pid: 9, currentPID: 10, parentPID: 9) == .parentProcess)
    }

    @Test
    func allowsOtherPositivePIDs() {
        #expect(PortKillPolicy.validate(pid: 11, currentPID: 10, parentPID: 9) == nil)
    }
}
