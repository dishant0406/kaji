import CEFBridge
import Foundation

@MainActor
final class DroidBrowserRuntimeCoordinator {
    static let shared = DroidBrowserRuntimeCoordinator()

    private var runtimeInfo: DroidBrowserRuntimeInfo?

    private init() {}

    func ensureStarted(projectPath _: String) throws -> DroidBrowserRuntimeInfo {
        if let runtimeInfo { return runtimeInfo }
        guard let rootPath = CEFRuntimeLocator.rootPath() else { throw DroidBrowserRuntimeError.runtimeMissing }
        guard let helperPath = CEFRuntimeLocator.helperPath(rootPath: rootPath) else { throw DroidBrowserRuntimeError.helperMissing }
        let broker = DroidBrowserControlBroker.shared.ensureStarted()
        let remotePort = Int(DroidBrowserDebugPort.allocate())
        let profilePath = Self.profilePath()
        try FileManager.default.createDirectory(atPath: profilePath, withIntermediateDirectories: true)
        try DroidCEFRuntime.start(
            withRootPath: rootPath,
            profilePath: profilePath,
            helperPath: helperPath,
            remoteDebuggingPort: Int32(remotePort)
        )
        let info = DroidBrowserRuntimeInfo(
            rootPath: rootPath,
            profilePath: profilePath,
            helperPath: helperPath,
            remoteDebuggingPort: remotePort
        )
        runtimeInfo = info
        if broker != nil {
            DroidBrowserControlBroker.shared.updateRuntime(info)
        }
        return info
    }

    func currentRuntime() -> DroidBrowserRuntimeInfo? {
        runtimeInfo
    }

    static func profilePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["DROID_CEF_PROFILE_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return override
        }

        return DroidFileStorage.appSupportDirectory()
            .appendingPathComponent("CEFProfile", isDirectory: true)
            .path
    }
}
