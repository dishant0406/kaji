import Foundation

struct KajiCodeHookInstallOutcome: Equatable {
    let hookID: String
    let installed: Bool
    let detail: String
}

enum KajiCodeHookInstallService {
    static let hookIDs = hooks.map(\.id)

    private static let hooks: [KajiCodeHookSpec] = [
        KajiCodeHookSpec(id: "kaji.session-start", event: "sessionStart", name: "Kaji session start"),
        KajiCodeHookSpec(id: "kaji.session-end", event: "sessionEnd", name: "Kaji session end"),
        KajiCodeHookSpec(id: "kaji.before-tool", event: "beforeTool", name: "Kaji tool start"),
        KajiCodeHookSpec(id: "kaji.after-tool", event: "afterTool", name: "Kaji tool end"),
        KajiCodeHookSpec(id: "kaji.specialist-start", event: "specialistStart", name: "Kaji specialist start"),
        KajiCodeHookSpec(id: "kaji.specialist-stop", event: "specialistStop", name: "Kaji specialist stop"),
    ]

    static func install(
        binaryURL: URL,
        hookClientPath: String,
        runner: any KajiCodeCLICommandRunning = KajiCodeCLICommandRunner()
    ) throws -> [KajiCodeHookInstallOutcome] {
        try hooks.map { hook in
            let args = addArguments(hook: hook, hookClientPath: hookClientPath)
            let result = try runner.run(binaryURL: binaryURL, arguments: args, timeout: 20)
            return outcome(hookID: hook.id, result: result, installed: true)
        }
    }

    static func uninstall(
        binaryURL: URL,
        runner: any KajiCodeCLICommandRunning = KajiCodeCLICommandRunner()
    ) throws -> [KajiCodeHookInstallOutcome] {
        try hooks.map { hook in
            let result = try runner.run(
                binaryURL: binaryURL,
                arguments: ["hooks", "remove", hook.id, "--user", "--json"],
                timeout: 20
            )
            return outcome(hookID: hook.id, result: result, installed: false)
        }
    }

    private static func addArguments(
        hook: KajiCodeHookSpec,
        hookClientPath: String
    ) -> [String] {
        [
            "hooks", "add", hook.id,
            "--event", hook.event,
            "--command", "/bin/sh",
            "--arg", "-c",
            "--arg", hookScript,
            "--arg", "kajicode-kaji-hook",
            "--arg", hook.event,
            "--arg", hookClientPath,
            "--name", hook.name,
            "--description", "Emit Kaji activity for KajiCode",
            "--user",
            "--json",
        ]
    }

    private static var hookScript: String {
        "client=${KAJI_HOOK_CLIENT_PATH:-$2}; if [ -x \"$client\" ]; then \"$client\" kajicode-hook \"$1\"; fi; exit 0"
    }

    private static func outcome(
        hookID: String,
        result: KajiCodeCLICommandResult,
        installed: Bool
    ) -> KajiCodeHookInstallOutcome {
        KajiCodeHookInstallOutcome(
            hookID: hookID,
            installed: installed && result.exitCode == 0,
            detail: result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct KajiCodeHookSpec {
    let id: String
    let event: String
    let name: String
}
