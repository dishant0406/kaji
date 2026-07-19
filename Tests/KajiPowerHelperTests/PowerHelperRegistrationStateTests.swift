import Testing
@testable import KajiPowerHelperProtocol

struct PowerHelperRegistrationStateTests {
    @Test func mapsServiceRegistrationStatesWithoutClaimingReadiness() {
        #expect(PowerHelperRegistrationState.resolve(status: .notRegistered) == .notRegistered)
        #expect(PowerHelperRegistrationState.resolve(status: .notFound) == .notRegistered)
        #expect(PowerHelperRegistrationState.resolve(status: .requiresApproval) == .requiresApproval)
        #expect(PowerHelperRegistrationState.resolve(status: .unknown) == .unavailable)
        #expect(PowerHelperRegistrationState.resolve(status: .enabled, sleepDisabled: true) == .ready(sleepDisabled: true))
        #expect(PowerHelperRegistrationState.resolve(status: .enabled, sleepDisabled: false) == .ready(sleepDisabled: false))
    }
}
