import CEFBridge
import Foundation

@MainActor
final class KajiBrowserRuntimeCoordinator {
    static let shared = KajiBrowserRuntimeCoordinator()

    private var runtimeInfo: KajiBrowserRuntimeInfo?

    private init() {}

    func ensureStarted(projectPath _: String) throws -> KajiBrowserRuntimeInfo {
        if let runtimeInfo { return runtimeInfo }
        let profileURL = try KajiCEFProfileRecovery.prepareProfile(at: Self.profileURL())
        guard let rootPath = CEFRuntimeLocator.rootPath() else { throw KajiBrowserRuntimeError.runtimeMissing }
        guard let helperPath = CEFRuntimeLocator.helperPath(rootPath: rootPath) else { throw KajiBrowserRuntimeError.helperMissing }
        let broker = KajiBrowserControlBroker.shared.ensureStarted()
        let remotePort = Int(KajiBrowserDebugPort.allocate())
        let profilePath = profileURL.path
        try KajiCEFRuntime.start(
            withRootPath: rootPath,
            profilePath: profilePath,
            helperPath: helperPath,
            remoteDebuggingPort: Int32(remotePort)
        )
        let info = KajiBrowserRuntimeInfo(
            rootPath: rootPath,
            profilePath: profilePath,
            helperPath: helperPath,
            remoteDebuggingPort: remotePort
        )
        runtimeInfo = info
        if broker != nil {
            KajiBrowserControlBroker.shared.updateRuntime(info)
        }
        return info
    }

    func markBrowserStartupComplete() {
        guard let runtimeInfo else { return }
        KajiCEFProfileRecovery.markStarted(profileURL: URL(fileURLWithPath: runtimeInfo.profilePath, isDirectory: true))
    }

    func currentRuntime() -> KajiBrowserRuntimeInfo? {
        runtimeInfo
    }

    static func profilePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        profileURL(environment: environment).path
    }

    static func profileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["KAJI_CEF_PROFILE_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("CEFProfile", isDirectory: true)
    }
}
