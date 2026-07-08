import Testing

@testable import Kaji

@Suite("AI Gateway setup planner")
struct AIGatewaySetupPlannerTests {
    @Test("missing required fields disables setup")
    func validationDisablesSetup() {
        let plan = AIGatewaySetupPlanner.plan(
            settings: .defaults,
            status: .stopped,
            installState: .installed,
            validationMessage: "Paste the provider API key.",
            isWorking: false
        )

        #expect(plan.title == "Setup incomplete")
        #expect(plan.canRunPrimary == false)
    }

    @Test("not installed setup can run")
    func missingInstallCanSetup() {
        let plan = AIGatewaySetupPlanner.plan(
            settings: .defaults,
            status: .notInstalled,
            installState: .missing,
            validationMessage: nil,
            isWorking: false
        )

        #expect(plan.primaryTitle == "Set Up")
        #expect(plan.canRunPrimary == true)
    }

    @Test("stale install offers update restart")
    func staleInstallOffersUpdateRestart() {
        let plan = AIGatewaySetupPlanner.plan(
            settings: .defaults,
            status: .notInstalled,
            installState: .needsRepair("Installed AI Gateway is out of date."),
            validationMessage: nil,
            isWorking: false
        )

        #expect(plan.title == "Update required")
        #expect(plan.primaryTitle == "Update & Restart")
        #expect(plan.canRunPrimary == true)
    }

    @Test("running setup restarts")
    func runningRestarts() {
        let plan = AIGatewaySetupPlanner.plan(
            settings: .defaults,
            status: .running("http://localhost:5254"),
            installState: .installed,
            validationMessage: nil,
            isWorking: false
        )

        #expect(plan.title == "Running")
        #expect(plan.primaryTitle == "Apply & Restart")
    }
}
