import Foundation

enum KajiCodeGraphInstallerError: LocalizedError, Equatable {
    case commandFailed(String, Int32, String)
    case missingBundledAdapter

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, detail):
            "\(command) failed with status \(status). \(detail)"
        case .missingBundledAdapter:
            "Bundled KajiCodeGraph adapter is missing."
        }
    }
}

struct KajiCodeGraphInstaller {
    static let graphifyURL = "https://github.com/safishamsi/graphify.git"
    static let pinnedCommit = "441ac9fc38b3ff30c1b2e861d3b5fc6b54fbff48"

    let runner: any KajiCodeGraphProcessRunning

    init(runner: any KajiCodeGraphProcessRunning = KajiCodeGraphProcessRunner()) {
        self.runner = runner
    }

    @MainActor
    func install(store: KajiCodeGraphStore = .shared) async {
        do {
            let commit = try await installRuntime()
            store.markInstalled(commit: commit, message: "Installed")
        } catch {
            store.markFailed(error.localizedDescription)
        }
    }

    func installRuntime() async throws -> String? {
        try KajiCodeGraphDirectory.createBaseDirectories()
        try copyAdapter()
        try await ensureGraphifyClone()
        try await createVirtualEnvironment()
        try await installGraphifyDependencies()
        return try await readPinnedCommit()
    }

    private func ensureGraphifyClone() async throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: KajiCodeGraphDirectory.graphify.appendingPathComponent(".git").path) {
            try await run("git fetch", executable: "/usr/bin/env", arguments: [
                "git",
                "-C",
                KajiCodeGraphDirectory.graphify.path,
                "fetch",
                "--tags",
                "--prune",
                "origin",
            ])
        } else {
            try await run("git clone", executable: "/usr/bin/env", arguments: [
                "git",
                "clone",
                Self.graphifyURL,
                KajiCodeGraphDirectory.graphify.path,
            ])
        }
        try await run("git checkout", executable: "/usr/bin/env", arguments: [
            "git",
            "-C",
            KajiCodeGraphDirectory.graphify.path,
            "checkout",
            Self.pinnedCommit,
        ])
    }

    private func createVirtualEnvironment() async throws {
        if FileManager.default.isExecutableFile(atPath: KajiCodeGraphDirectory.python.path) {
            return
        }
        try await run("python venv", executable: "/usr/bin/env", arguments: [
            "python3",
            "-m",
            "venv",
            KajiCodeGraphDirectory.venv.path,
        ])
    }

    private func installGraphifyDependencies() async throws {
        try await run("pip install", executable: KajiCodeGraphDirectory.python.path, arguments: [
            "-m",
            "pip",
            "install",
            "--upgrade",
            "pip",
        ])
        try await run("graphify install", executable: KajiCodeGraphDirectory.python.path, arguments: [
            "-m",
            "pip",
            "install",
            "-e",
            "\(KajiCodeGraphDirectory.graphify.path)[pdf,office,watch,leiden,svg,openai,kimi,gemini,ollama,sql]",
        ])
    }

    private func readPinnedCommit() async throws -> String? {
        let result = try await runner.run(
            executable: "/usr/bin/env",
            arguments: ["git", "-C", KajiCodeGraphDirectory.graphify.path, "rev-parse", "HEAD"],
            workingDirectory: nil,
            environment: [:]
        )
        guard result.status == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyAdapter() throws {
        try Self.installBundledAdapter()
    }

    static func installBundledAdapter() throws {
        guard let source = Self.bundledAdapterURL else {
            throw KajiCodeGraphInstallerError.missingBundledAdapter
        }
        let destination = KajiCodeGraphDirectory.adapterScript
        try FileManager.default.createDirectory(
            at: KajiCodeGraphDirectory.adapter,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static var bundledAdapterURL: URL? {
        Bundle.module.url(forResource: "kajicodegraph_runner", withExtension: "py") ??
            Bundle.module.url(
                forResource: "kajicodegraph_runner",
                withExtension: "py",
                subdirectory: "kajicodegraph"
            )
    }

    private func run(_ name: String, executable: String, arguments: [String]) async throws {
        let result = try await runner.run(
            executable: executable,
            arguments: arguments,
            workingDirectory: KajiCodeGraphDirectory.root.path,
            environment: [:]
        )
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw KajiCodeGraphInstallerError.commandFailed(name, result.status, detail)
        }
    }
}
