import Foundation

actor RiftWorkspaceService {
    static let shared = RiftWorkspaceService()

    private let databaseURL: URL
    private let runnerFactory: @Sendable (URL) -> RiftProcessRunner

    init(
        databaseURL: URL = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("rift", isDirectory: true)
            .appendingPathComponent("rift.sqlite"),
        runnerFactory: @escaping @Sendable (URL) -> RiftProcessRunner = { RiftProcessRunner(binaryURL: $0) }
    ) {
        self.databaseURL = databaseURL
        self.runnerFactory = runnerFactory
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func initWorkspace(at path: String) async throws {
        _ = try await checkedRun(["init", path, "--here"], workingDirectory: path)
    }

    func createWorkspace(from path: String, name: String, into: String? = nil) async throws -> String {
        try await initWorkspace(at: path)
        var arguments = ["create", path, "--name", name, "--copy-all", "--no-hooks"]
        if let into {
            arguments += ["--into", into]
        }
        let result = try await checkedRun(arguments, workingDirectory: path)
        let createdPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !createdPath.isEmpty else { throw RiftWorkspaceError.emptyCreateOutput }
        return createdPath
    }

    func listWorkspaces(of path: String) async throws -> [RiftWorkspaceRecord] {
        try await initWorkspace(at: path)
        let result = try await checkedRun(["list", path], workingDirectory: path)
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { RiftWorkspaceRecord(path: $0, riftID: riftID(at: $0)) }
    }

    func removeWorkspace(at path: String) async throws {
        _ = try await checkedRun(["remove", path], workingDirectory: path)
    }

    func gc(workingDirectory: String) async throws {
        _ = try await checkedRun(["gc"], workingDirectory: workingDirectory)
    }

    func riftID(at path: String) -> String? {
        let marker = URL(fileURLWithPath: path).appendingPathComponent(".rift")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func checkedRun(_ arguments: [String], workingDirectory: String? = nil) async throws -> RiftProcessResult {
        guard let binaryURL = RiftBinaryLocator.url() else { throw RiftWorkspaceError.binaryUnavailable }
        let result = try await runnerFactory(binaryURL).run(
            arguments: ["--database", databaseURL.path] + arguments,
            workingDirectory: workingDirectory
        )
        guard result.status == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw RiftWorkspaceError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}
