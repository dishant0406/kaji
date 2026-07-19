import Testing
@testable import KajiPowerHelper

struct PowerHelperSecurityTests {
    @Test func requirementPinsAppleAnchorIdentifierAndTeam() {
        let requirement = PowerHelperCodeSigningRequirement.designated(
            identifier: "com.kaji.app",
            teamIdentifier: "TEAM123"
        )
        #expect(requirement == "anchor apple generic and identifier \"com.kaji.app\" and certificate leaf[subject.OU] = \"TEAM123\"")
    }

    @Test func requirementEscapesInjectedValues() {
        let requirement = PowerHelperCodeSigningRequirement.designated(
            identifier: "com.kaji.\" or true",
            teamIdentifier: "TEAM\\123"
        )
        #expect(requirement.contains("com.kaji.\\\" or true"))
        #expect(requirement.contains("TEAM\\\\123"))
    }
}
