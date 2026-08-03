import Foundation
import os

private let logger = Logger(subsystem: "app.kaji", category: "AIProviderRegistry")

protocol AIProviderIntegration: Sendable {
    var id: String { get }
    var displayName: String { get }
    var socketTypeKey: String { get }
    var iconName: String { get }
    var executableNames: [String] { get }

    func isToolInstalled() -> Bool
    func install(hookClientPath: String) throws
    func uninstall() throws
}

extension AIProviderIntegration {
    var settingsKey: String { "kaji.notifications.provider.\(id).enabled" }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: settingsKey, fallback: true) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: settingsKey) }
    }

    func isToolInstalled() -> Bool {
        AIProviderExecutableLocator.isInstalled(executableNames: executableNames)
    }
}

@MainActor
final class AIProviderRegistry {
    static let shared = AIProviderRegistry()

    var providers: [AIProviderIntegration] {
        CodingAgentRegistry.shared.agents.map { $0 as AIProviderIntegration }
    }

    lazy var usageProviders: [any AIUsageProvider] = CodingAgentRegistry.shared.agents.compactMap { module in
        (module as? any CodingAgentModule & AIUsageProvider).map(CodingAgentUsageAdapter.init(module:))
    } + [
        CopilotUsageProvider(),
        AmpUsageProvider(),
        ZaiUsageProvider(),
        MiniMaxUsageProvider(),
        KimiUsageProvider(),
        FactoryUsageProvider(),
    ]

    private init() {}

    func installAll() {
        let providers = providers
        Task.detached(priority: .utility) {
            await AIProviderIntegrationSyncService.installAll(providers)
        }
    }

    func installAllNow() async {
        await AIProviderIntegrationSyncService.installAll(providers)
    }

    func forceInstall(_ provider: AIProviderIntegration) async {
        await AIProviderIntegrationSyncService.forceInstall(provider)
    }

    func uninstallAll() {
        let providers = providers
        Task.detached(priority: .utility) {
            await AIProviderIntegrationSyncService.uninstallAll(providers)
        }
    }

    func notificationSource(for socketType: String) -> KajiNotification.Source {
        for provider in providers where provider.socketTypeKey == socketType {
            return .aiProvider(provider.id)
        }
        return .socket
    }

    func notificationPolicy(for source: KajiNotification.Source) -> CodingAgentNotificationPolicy {
        guard case let .aiProvider(id) = source,
              let definition = CodingAgentRegistry.shared.definition(id: id)
        else { return .default }
        return definition.notificationPolicy
    }

    func notificationPolicy(for socketType: String) -> CodingAgentNotificationPolicy {
        guard let provider = providers.first(where: { $0.socketTypeKey == socketType }),
              let definition = CodingAgentRegistry.shared.definition(id: provider.id)
        else { return .default }
        return definition.notificationPolicy
    }

    func iconName(for source: KajiNotification.Source) -> String {
        switch source {
        case .osc: "terminal"
        case let .aiProvider(id):
            AgentProviderCatalog.iconName(for: id)
        case .socket: "network"
        }
    }
}

enum AIProviderIntegrationSyncService {
    static func installAll(_ providers: [AIProviderIntegration]) async {
        await GitProcessRunner.offMain {
            installAllSync(providers)
        }
    }

    static func forceInstall(_ provider: AIProviderIntegration) async {
        await GitProcessRunner.offMain {
            forceInstallSync(provider)
        }
    }

    static func uninstallAll(_ providers: [AIProviderIntegration]) async {
        await GitProcessRunner.offMain {
            uninstallAllSync(providers)
        }
    }

    private static func installAllSync(_ providers: [AIProviderIntegration]) {
        guard let hookClientPath = KajiNotificationHooks.hookClientPath else {
            logger.info("Hook client not found, skipping AI provider installs")
            return
        }

        for provider in providers {
            guard provider.isEnabled else {
                try? provider.uninstall()
                continue
            }
            guard provider.isToolInstalled() else { continue }
            do {
                try provider.install(hookClientPath: hookClientPath)
                logger.info("Installed \(provider.displayName) integration")
            } catch {
                logger.error("Failed to install \(provider.displayName): \(error.localizedDescription)")
            }
        }
    }

    private static func forceInstallSync(_ provider: AIProviderIntegration) {
        guard let hookClientPath = KajiNotificationHooks.hookClientPath else {
            logger.info("Hook client not found, skipping force install")
            return
        }

        do {
            try provider.uninstall()
            try provider.install(hookClientPath: hookClientPath)
            logger.info("Force-installed \(provider.displayName) integration")
        } catch {
            logger.error("Failed to force-install \(provider.displayName): \(error.localizedDescription)")
        }
    }

    private static func uninstallAllSync(_ providers: [AIProviderIntegration]) {
        for provider in providers {
            do {
                try provider.uninstall()
            } catch {
                logger.error("Failed to uninstall \(provider.displayName): \(error.localizedDescription)")
            }
        }
    }
}
