import Testing

@testable import Kaji

struct GitCommandParserTests {
    @Test
    func parsesGitCommandState() {
        let state = GitCommandParser.state(for: ":git fetch --all")

        #expect(state?.command == .git)
        #expect(state?.filter == "fetch --all")
    }

    @Test
    func parsesQuotedArguments() throws {
        let arguments = try GitCommandParser.arguments(from: "commit -m \"hello world\"")

        #expect(arguments == ["commit", "-m", "hello world"])
    }

    @Test
    func allowsColonInsideGitArguments() {
        let state = GitCommandParser.state(for: ":git commit -m \"feat: branch picker\"")

        #expect(state?.command == .git)
        #expect(state?.filter == "commit -m \"feat: branch picker\"")
    }

    @Test
    func blocksInteractiveCommit() {
        let request = GitCommandParser.request(command: .git, input: "commit")

        #expect(request.blockedMessage != nil)
        #expect(!request.canRun)
    }

    @Test
    func confirmsHardReset() {
        let request = GitCommandParser.request(command: .git, input: "reset --hard")

        #expect(request.confirmationMessage != nil)
        #expect(request.canRun)
    }

    @Test
    func checkoutPrependsGitCheckout() {
        let request = GitCommandParser.request(command: .checkout, input: "main")

        #expect(request.arguments == ["checkout", "main"])
        #expect(request.displayCommand == "git checkout main")
    }
}
