import Foundation
import Testing

@testable import Kaji

struct KajiCodeHookInstallServiceTests {
    @Test
    func installsAllKajiHooksWithFailOpenShellWrapper() throws {
        let runner = RecordingKajiCodeRunner()
        let binary = URL(fileURLWithPath: "/tmp/kajicode")

        let outcomes = try KajiCodeHookInstallService.install(
            binaryURL: binary,
            hookClientPath: "/Applications/Kaji.app/Contents/MacOS/KajiHookClient",
            runner: runner
        )

        #expect(outcomes.count == 6)
        #expect(outcomes.allSatisfy { $0.installed })
        #expect(runner.calls.count == 6)
        let beforeTool = try #require(runner.calls.first { $0.arguments.contains("beforeTool") })
        #expect(beforeTool.binaryURL == binary)
        #expect(beforeTool.arguments.contains("hooks"))
        #expect(beforeTool.arguments.contains("add"))
        #expect(beforeTool.arguments.contains("kaji.before-tool"))
        #expect(beforeTool.arguments.contains("/bin/sh"))
        #expect(beforeTool.arguments.contains { $0.contains("KAJI_HOOK_CLIENT_PATH") })
        #expect(beforeTool.arguments.contains("--user"))
        #expect(beforeTool.arguments.contains("--json"))
    }

    @Test
    func uninstallsKnownKajiHooksFromUserScope() throws {
        let runner = RecordingKajiCodeRunner()

        let outcomes = try KajiCodeHookInstallService.uninstall(
            binaryURL: URL(fileURLWithPath: "/tmp/kajicode"),
            runner: runner
        )

        #expect(outcomes.count == 6)
        #expect(outcomes.allSatisfy { !$0.installed })
        #expect(runner.calls.allSatisfy { call in
            call.arguments.prefix(2).elementsEqual(["hooks", "remove"]) &&
                call.arguments.contains("--user") &&
                call.arguments.contains("--json")
        })
    }
}

private final class RecordingKajiCodeRunner: KajiCodeCLICommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let binaryURL: URL
        let arguments: [String]
        let environment: [String: String]?
    }

    var calls = [Call]()

    func run(
        binaryURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout _: TimeInterval
    ) throws -> KajiCodeCLICommandResult {
        calls.append(Call(binaryURL: binaryURL, arguments: arguments, environment: environment))
        return KajiCodeCLICommandResult(exitCode: 0, output: "{}")
    }
}
