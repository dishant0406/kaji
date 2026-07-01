import Testing

@testable import Kaji

struct TerminalEnvironmentPolicyTests {
    @Test
    func stripsNoColorFromInheritedEnvironment() {
        let result = TerminalEnvironmentPolicy.sanitizedEnvironment(
            from: [
                "NO_COLOR": "1",
                "COLORTERM": "truecolor",
                "PATH": "/usr/bin",
            ]
        )

        #expect(result["NO_COLOR"] == nil)
        #expect(result["COLORTERM"] == "truecolor")
        #expect(result["PATH"] == "/usr/bin")
    }
}
