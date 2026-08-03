import AppKit
import Foundation

protocol ExternalIDEApplicationResolving: Sendable {
    func applicationURL(for bundleIdentifier: String) -> URL?
    func fastExecutablePath(for executableName: String) -> String?
    func shellExecutablePath(for executableName: String) async -> String?
    func fileExists(atPath path: String) -> Bool
}

struct ExternalIDEApplicationResolver: ExternalIDEApplicationResolving {
    private let env: [String: String]
    private let homeDirectory: String

    init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.env = env
        self.homeDirectory = homeDirectory
    }

    func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func fastExecutablePath(for executableName: String) -> String? {
        AIProviderExecutableLocator.resolvePath(
            for: executableName,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: .default
        )
    }

    func shellExecutablePath(for executableName: String) async -> String? {
        await GitProcessRunner.offMain {
            AIProviderExecutableLocator.resolvePath(
                for: executableName,
                env: env,
                homeDirectory: homeDirectory,
                fileManager: .default
            )
        }
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
