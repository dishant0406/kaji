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
        let context = await executionContext(configuredCommand: configuredCommand)
        if let resolution = context.resolution,
           resolution.source != .managed
        {
            return await setupExisting(resolution: resolution, environment: context.environment)
        }
        let install = await KajiCodeInstaller.installLatest()
        guard case .installed = install.state else { return install }
        return await setupExisting()
    }

    static func uninstall() async -> KajiCodeInstallResult {
        await GitProcessRunner.offMain {
            let context = synchronousExecutionContext(configuredCommand: nil)
            if let resolution = context.resolution {
                try? KajiCodeAgentModule().uninstall(binaryURL: resolution.binaryURL, environment: context.environment)
            }
            _ = KajiCodeMCPInstallService.uninstallAll()
            return KajiCodeInstaller.uninstall()
        }
    }

    private static func setupExisting(
        resolution resolvedRuntime: KajiCodeRuntimeResolution? = nil,
        environment resolvedEnvironment: [String: String]? = nil
    ) async -> KajiCodeInstallResult {
        do {
            let context = if let resolvedRuntime {
                (resolution: Optional(resolvedRuntime), environment: resolvedEnvironment ?? executionEnvironment())
            } else {
                await executionContext(configuredCommand: nil)
            }
            guard let resolution = context.resolution else { throw KajiCodeSetupError.binaryMissing }
            guard let hookClientPath = KajiNotificationHooks.hookClientPath else { throw KajiCodeSetupError.hookClientMissing }
            let smoke = try await KajiCodeSmokeTester.smoke(
                binaryURL: resolution.binaryURL,
                expectedVersion: nil,
                environment: context.environment
            )
            guard smoke.localizedCaseInsensitiveContains("kajicode") else {
                throw KajiCodeInstallError.smokeFailed("KajiCode version output was not recognized.")
            }
            let installed = try await GitProcessRunner.offMainThrowing {
                _ = try KajiCodeAgentModule().install(
                    binaryURL: resolution.binaryURL,
                    hookClientPath: hookClientPath,
                    environment: context.environment
                )
                let mcpOutcomes = KajiCodeMCPInstallService.installAll(
                    binaryURL: resolution.binaryURL,
                    environment: ShellExecutionEnvironmentResolver.mcpEnvironment(from: context.environment)
                )
                return mcpOutcomes.filter(\.installed).count
            }
            let state = await GitProcessRunner.offMain { KajiCodeInstaller.state() }
            return .init(
                state: state,
                message: "\(smoke) hooks installed and MCP registered for \(installed) agents."
            )
        } catch {
            return .init(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }

    private static func executionContext(
        configuredCommand: String?
    ) async -> (resolution: KajiCodeRuntimeResolution?, environment: [String: String]) {
        await GitProcessRunner.offMain {
            synchronousExecutionContext(configuredCommand: configuredCommand)
        }
    }

    private static func synchronousExecutionContext(
        configuredCommand: String?
    ) -> (resolution: KajiCodeRuntimeResolution?, environment: [String: String]) {
        let environment = executionEnvironment()
        let resolution = KajiCodeRuntimeLocator.resolve(configuredCommand: configuredCommand, env: environment)
        return (resolution, environment)
    }

    private static func executionEnvironment() -> [String: String] {
        ShellExecutionEnvironmentResolver.resolve()
    }
}
