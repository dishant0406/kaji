import Foundation

enum KajiCodeSetupError: LocalizedError {
    case hookClientMissing
    case binaryMissing

    var errorDescription: String? {
        switch self {
        case .hookClientMissing: "Kaji hook client is missing."
        case .binaryMissing: "KajiCode binary is missing."
        }
    }
}

enum KajiCodeSetupService {
    static func installOrUpdate(configuredCommand: String? = nil) async -> KajiCodeInstallResult {
        if let resolution = KajiCodeRuntimeLocator.resolve(configuredCommand: configuredCommand),
           resolution.source != .managed
        {
            return await setupExisting(resolution: resolution)
        }
        let install = await KajiCodeInstaller.installLatest()
        guard case .installed = install.state else { return install }
        return await setupExisting()
    }

    static func uninstall() -> KajiCodeInstallResult {
        if let resolution = KajiCodeRuntimeLocator.resolve() {
            try? KajiCodeAgentModule().uninstall(binaryURL: resolution.binaryURL)
        }
        _ = KajiCodeMCPInstallService.uninstallAll()
        return KajiCodeInstaller.uninstall()
    }

    private static func setupExisting(resolution resolvedRuntime: KajiCodeRuntimeResolution? = nil) async -> KajiCodeInstallResult {
        do {
            guard let resolution = resolvedRuntime ?? KajiCodeRuntimeLocator.resolve() else { throw KajiCodeSetupError.binaryMissing }
            guard let hookClientPath = KajiNotificationHooks.hookClientPath else { throw KajiCodeSetupError.hookClientMissing }
            let smoke = try await KajiCodeSmokeTester.smoke(binaryURL: resolution.binaryURL, expectedVersion: nil)
            guard smoke.localizedCaseInsensitiveContains("kajicode") else {
                throw KajiCodeInstallError.smokeFailed("KajiCode version output was not recognized.")
            }
            _ = try KajiCodeAgentModule().install(binaryURL: resolution.binaryURL, hookClientPath: hookClientPath)
            let mcpOutcomes = KajiCodeMCPInstallService.installAll(binaryURL: resolution.binaryURL)
            let installed = mcpOutcomes.filter(\.installed).count
            return .init(
                state: KajiCodeInstaller.state(),
                message: "\(smoke) hooks installed and MCP registered for \(installed) agents."
            )
        } catch {
            return .init(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }
}
