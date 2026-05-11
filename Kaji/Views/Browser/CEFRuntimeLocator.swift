import Foundation

enum CEFRuntimeLocator {
    static func rootPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let paths = [
            environment["KAJI_CEF_ROOT"],
            bundledFrameworksPath(),
            mainResourcePath("CEFRuntime/cef_binary"),
            projectPath(".dev-support/cef-runtime/cef_binary"),
        ].compactMap(\.self)
        return paths.first { containsFramework($0) || FileManager.default.fileExists(atPath: $0) }
    }

    static func helperPath(rootPath: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let paths = [
            environment["KAJI_CEF_HELPER_PATH"],
            URL(fileURLWithPath: rootPath).appendingPathComponent("cefsimple Helper.app/Contents/MacOS/cefsimple Helper").path,
            mainResourcePath("CEFRuntime/Helpers/cefsimple Helper.app/Contents/MacOS/cefsimple Helper"),
            projectPath(".dev-support/cef-runtime/build/tests/cefsimple/Release/cefsimple Helper.app/Contents/MacOS/cefsimple Helper"),
            URL(fileURLWithPath: rootPath)
                .deletingLastPathComponent()
                .appendingPathComponent("build/tests/cefsimple/Release/cefsimple Helper.app/Contents/MacOS/cefsimple Helper")
                .path,
        ].compactMap(\.self)
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func mainResourcePath(_ path: String) -> String? {
        Bundle.main.resourceURL?.appendingPathComponent(path).path
    }

    private static func bundledFrameworksPath() -> String? {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path
    }

    private static func containsFramework(_ path: String) -> Bool {
        FileManager.default
            .fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("Chromium Embedded Framework.framework").path)
    }

    private static func projectPath(_ path: String) -> String {
        FileManager.default.currentDirectoryPath.appending("/\(path)")
    }
}
