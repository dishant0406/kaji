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
    static func installOrUpdate() async -> KajiCodeInstallResult {
        if KajiCodeRuntimeLocator.resolve()?.source == .developerOverride {
            return setupExisting()
        }
        let install = await KajiCodeInstaller.installLatest()
        guard case .installed = install.state else { return install }
        return setupExisting()
    }

    static func uninstall() -> KajiCodeInstallResult {
        if let resolution = KajiCodeRuntimeLocator.resolve() {
            try? KajiCodeAgentModule().uninstall(binaryURL: resolution.binaryURL)
        }
        _ = KajiCodeMCPInstallService.uninstallAll()
        return KajiCodeInstaller.uninstall()
    }

    private static func setupExisting() -> KajiCodeInstallResult {
        do {
            guard let resolution = KajiCodeRuntimeLocator.resolve() else { throw KajiCodeSetupError.binaryMissing }
            guard let hookClientPath = KajiNotificationHooks.hookClientPath else { throw KajiCodeSetupError.hookClientMissing }
            _ = try KajiCodeAgentModule().install(binaryURL: resolution.binaryURL, hookClientPath: hookClientPath)
            let mcpOutcomes = KajiCodeMCPInstallService.installAll(binaryURL: resolution.binaryURL)
            let installed = mcpOutcomes.filter(\.installed).count
            return .init(state: KajiCodeInstaller.state(), message: "KajiCode hooks installed and MCP registered for \(installed) agents.")
        } catch {
            return .init(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }
}
