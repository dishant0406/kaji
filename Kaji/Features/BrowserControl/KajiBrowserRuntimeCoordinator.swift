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
        let rootCachePath = Self.rootCachePath(profileURL: profileURL)
        DebugFileLog.log(
            "Browser",
            "CEF start requested root=\(rootPath) profile=\(profilePath) rootCache=\(rootCachePath) helper=\(helperPath) port=\(remotePort)"
        )
        try KajiCEFRuntime.start(
            withRootPath: rootPath,
            profilePath: profilePath,
            rootCachePath: rootCachePath,
            helperPath: helperPath,
            remoteDebuggingPort: Int32(remotePort)
        )
        let info = KajiBrowserRuntimeInfo(
            rootPath: rootPath,
            profilePath: profilePath,
            rootCachePath: rootCachePath,
            helperPath: helperPath,
            remoteDebuggingPort: remotePort
        )
        runtimeInfo = info
        if broker != nil {
            KajiBrowserControlBroker.shared.updateRuntime(info)
        }
        DebugFileLog.log("Browser", "CEF start completed profile=\(profilePath) port=\(remotePort)")
        return info
    }

    func markBrowserStartupComplete() {
        guard let runtimeInfo else { return }
        KajiCEFProfileRecovery.markStarted(profileURL: URL(fileURLWithPath: runtimeInfo.profilePath, isDirectory: true))
        DebugFileLog.log("Browser", "CEF startup marked complete profile=\(runtimeInfo.profilePath)")
    }

    func shutdownForTermination() {
        guard let runtimeInfo else { return }
        let profileURL = URL(fileURLWithPath: runtimeInfo.profilePath, isDirectory: true)
        DebugFileLog.log("Browser", "CEF shutdown requested profile=\(runtimeInfo.profilePath)")
        KajiCEFRuntime.shutdown()
        KajiCEFProfileRecovery.markCleanShutdown(profileURL: profileURL)
        self.runtimeInfo = nil
        DebugFileLog.log("Browser", "CEF shutdown completed profile=\(profileURL.path)")
    }

    func currentRuntime() -> KajiBrowserRuntimeInfo? {
        runtimeInfo
    }

    static func profilePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        profileURL(environment: environment).path
    }

    static func rootCachePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        rootCachePath(profileURL: profileURL(environment: environment))
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

    private static func rootCachePath(profileURL: URL) -> String {
        profileURL.path
    }
}
