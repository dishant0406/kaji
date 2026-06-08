import Foundation
import Testing

@testable import Kaji

struct UserCommandShortcutResolverTests {
    @Test
    func resolvesNamedVariablesWithShellEscaping() async throws {
        let shortcut = UserCommandShortcut(name: "Echo", slug: "echo", command: "echo {message}")
        let result = await UserCommandShortcutResolver.resolve(
            shortcut: shortcut,
            state: state("::echo \"hello; rm -rf /\""),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let plan = try plan(from: result)
        #expect(plan.arguments == ["-lc", "echo 'hello; rm -rf /'"])
    }

    @Test
    func resolvesPositionalVariables() async throws {
        let shortcut = UserCommandShortcut(name: "Push", slug: "push", command: "git push {1} {2}")
        let result = await UserCommandShortcutResolver.resolve(
            shortcut: shortcut,
            state: state("::push origin main"),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let plan = try plan(from: result)
        #expect(plan.arguments == ["-lc", "git push origin main"])
    }

    @Test
    func failsWhenRequiredVariablesAreMissing() async {
        let shortcut = UserCommandShortcut(name: "Push", slug: "push", command: "git push origin {branchName}")
        let result = await UserCommandShortcutResolver.resolve(
            shortcut: shortcut,
            state: state("::push"),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(result == .failure(title: "::push", message: "Needs branchName."))
    }

    @Test
    func reportsMissingPositionalVariable() async {
        let shortcut = UserCommandShortcut(name: "Push", slug: "push", command: "git push {1} {2}")
        let result = await UserCommandShortcutResolver.resolve(
            shortcut: shortcut,
            state: state("::push origin"),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(result == .failure(title: "::push", message: "Needs 2."))
    }

    @Test
    func resolvesComputedVariablesWithShellEscaping() async throws {
        let shortcut = UserCommandShortcut(name: "Push", slug: "push", command: "git push origin {~git branch --show-current~}")
        let result = await UserCommandShortcutResolver.resolve(
            shortcut: shortcut,
            state: state("::push"),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            computedValueRunner: { command, _ in command == "git branch --show-current" ? .success("feature/login") : .failure("bad") }
        )

        let plan = try plan(from: result)
        #expect(plan.arguments == ["-lc", "git push origin feature/login"])
    }

    private func state(_ text: String) -> UserCommandShortcutState {
        UserCommandShortcutParser.state(for: text) ?? .init(slug: "", rawArguments: "", arguments: [], argumentError: nil)
    }

    private func plan(from result: UserCommandShortcutResolveResult) throws -> NativeCommandRunPlan {
        guard case let .plan(plan) = result else {
            throw TestError.unexpectedResult
        }
        return plan
    }

    private enum TestError: Error {
        case unexpectedResult
    }
}
