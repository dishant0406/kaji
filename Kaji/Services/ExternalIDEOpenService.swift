import AppKit
import Foundation

enum ExternalIDEOpenError: LocalizedError, Equatable {
    case projectMissing(String)
    case applicationMissing(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .projectMissing(path):
            "Project folder does not exist: \(path)"
        case let .applicationMissing(name):
            "\(name) is not installed or cannot be resolved."
        case let .launchFailed(message):
            message
        }
    }
}

@MainActor
protocol ExternalIDEWorkspaceOpening {
    func open(urls: [URL], applicationURL: URL, arguments: [String]) async throws
}

@MainActor
protocol ExternalIDECommandOpening {
    func open(executablePath: String, arguments: [String]) async throws
}

struct ExternalIDEWorkspaceOpener: ExternalIDEWorkspaceOpening {
    func open(urls: [URL], applicationURL: URL, arguments: [String]) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct ExternalIDECommandOpener: ExternalIDECommandOpening {
    func open(executablePath: String, arguments: [String]) async throws {
        try await GitProcessRunner.offMainThrowing {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            try process.run()
        }
    }
}

struct ExternalIDEOpenService {
    let catalog: ExternalIDECatalog
    let workspaceOpener: ExternalIDEWorkspaceOpening
    let commandOpener: ExternalIDECommandOpening
    let fileManager: FileManager

    init(
        catalog: ExternalIDECatalog = ExternalIDECatalog(),
        workspaceOpener: ExternalIDEWorkspaceOpening = ExternalIDEWorkspaceOpener(),
        commandOpener: ExternalIDECommandOpening = ExternalIDECommandOpener(),
        fileManager: FileManager = .default
    ) {
        self.catalog = catalog
        self.workspaceOpener = workspaceOpener
        self.commandOpener = commandOpener
        self.fileManager = fileManager
    }

    @MainActor
    func open(projectPath: String, in ide: ExternalIDE) async throws {
        let url = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExternalIDEOpenError.projectMissing(url.path)
        }
        do {
            if let appURL = catalog.resolvedApplicationURL(for: ide) {
                try await workspaceOpener.open(urls: [url], applicationURL: appURL, arguments: ide.launchArguments)
                return
            }
            if let executablePath = await catalog.resolvedExecutablePathIncludingShell(for: ide) {
                try await commandOpener.open(executablePath: executablePath, arguments: ide.launchArguments + [url.path])
                return
            }
            throw ExternalIDEOpenError.applicationMissing(ide.displayName)
        } catch {
            if (error as? ExternalIDEOpenError) != nil { throw error }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw ExternalIDEOpenError.launchFailed(message)
        }
    }
}
