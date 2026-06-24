import Foundation
import Testing

@testable import Kaji

struct ExternalIDEOpenServiceTests {
    @Test
    @MainActor
    func opensProjectWithResolvedApplication() async throws {
        let project = try temporaryDirectory()
        let appURL = URL(fileURLWithPath: "/Applications/Code.app")
        let resolver = ExternalIDEFakeResolver(
            applications: ["com.example.Editor": appURL],
            existingPaths: [appURL.path]
        )
        let workspaceOpener = RecordingWorkspaceOpener()
        let service = ExternalIDEOpenService(
            catalog: ExternalIDECatalog(resolver: resolver),
            workspaceOpener: workspaceOpener,
            commandOpener: RecordingCommandOpener()
        )
        let ide = ExternalIDE(
            id: "editor",
            displayName: "Editor",
            bundleIdentifiers: ["com.example.Editor"]
        )

        try await service.open(projectPath: project.path, in: ide)

        let call = workspaceOpener.call
        #expect(call?.urls == [project.standardizedFileURL])
        #expect(call?.applicationURL == appURL)
    }

    @Test
    @MainActor
    func fallsBackToResolvedExecutable() async throws {
        let project = try temporaryDirectory()
        let resolver = ExternalIDEFakeResolver(executables: ["editor": "/usr/local/bin/editor"])
        let commandOpener = RecordingCommandOpener()
        let service = ExternalIDEOpenService(
            catalog: ExternalIDECatalog(resolver: resolver),
            workspaceOpener: RecordingWorkspaceOpener(),
            commandOpener: commandOpener
        )
        let ide = ExternalIDE(
            id: "editor",
            displayName: "Editor",
            bundleIdentifiers: [],
            executableNames: ["editor"],
            launchArguments: ["--reuse-window"]
        )

        try await service.open(projectPath: project.path, in: ide)

        let call = commandOpener.call
        #expect(call?.executablePath == "/usr/local/bin/editor")
        #expect(call?.arguments == ["--reuse-window", project.standardizedFileURL.path])
    }

    @Test
    @MainActor
    func fallsBackToShellResolvedExecutable() async throws {
        let project = try temporaryDirectory()
        let resolver = ExternalIDEFakeResolver(shellExecutables: ["editor": "/opt/homebrew/bin/editor"])
        let commandOpener = RecordingCommandOpener()
        let service = ExternalIDEOpenService(
            catalog: ExternalIDECatalog(resolver: resolver),
            workspaceOpener: RecordingWorkspaceOpener(),
            commandOpener: commandOpener
        )
        let ide = ExternalIDE(
            id: "editor",
            displayName: "Editor",
            bundleIdentifiers: [],
            executableNames: ["editor"]
        )

        try await service.open(projectPath: project.path, in: ide)

        #expect(commandOpener.call?.executablePath == "/opt/homebrew/bin/editor")
        #expect(commandOpener.call?.arguments == [project.standardizedFileURL.path])
    }

    @Test
    @MainActor
    func throwsWhenProjectIsMissing() async throws {
        let resolver = ExternalIDEFakeResolver(
            applications: ["com.example.Editor": URL(fileURLWithPath: "/Applications/Editor.app")]
        )
        let service = ExternalIDEOpenService(catalog: ExternalIDECatalog(resolver: resolver))
        let ide = ExternalIDE(
            id: "editor",
            displayName: "Editor",
            bundleIdentifiers: ["com.example.Editor"]
        )

        do {
            try await service.open(projectPath: "/missing/project", in: ide)
            Issue.record("Expected missing project error")
        } catch let error as ExternalIDEOpenError {
            #expect(error == .projectMissing("/missing/project"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class RecordingWorkspaceOpener: ExternalIDEWorkspaceOpening {
    private(set) var call: (urls: [URL], applicationURL: URL, arguments: [String])?

    func open(urls: [URL], applicationURL: URL, arguments: [String]) async throws {
        call = (urls, applicationURL, arguments)
    }
}

@MainActor
final class RecordingCommandOpener: ExternalIDECommandOpening {
    private(set) var call: (executablePath: String, arguments: [String])?

    func open(executablePath: String, arguments: [String]) async throws {
        call = (executablePath, arguments)
    }
}
