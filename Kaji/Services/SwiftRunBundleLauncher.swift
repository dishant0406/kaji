import Foundation

enum SwiftRunBundleLauncher {
    static func relaunchIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        guard environment["KAJI_SWIFT_RUN_BUNDLE"] != "1" else { return }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        guard let projectRoot = projectRoot(fileManager: fileManager) else { return }
        let appURL = projectRoot.appendingPathComponent(".build/KajiSwiftRun.app", isDirectory: true)
        do {
            try prepareBundle(appURL: appURL, projectRoot: projectRoot, fileManager: fileManager)
            try launch(appURL: appURL, projectRoot: projectRoot, environment: environment)
            Darwin.exit(0)
        } catch {
            fputs("Kaji failed to launch app bundle: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func projectRoot(fileManager: FileManager) -> URL? {
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        if fileManager.fileExists(atPath: current.appendingPathComponent("Kaji/Info.plist").path) {
            return current
        }
        var cursor = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        while cursor.path != "/" {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent("Kaji/Info.plist").path) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    private static func prepareBundle(appURL: URL, projectRoot: URL, fileManager: FileManager) throws {
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        try writeInfoPlist(to: contents.appendingPathComponent("Info.plist"))
        try replaceLink(at: macOS.appendingPathComponent("Kaji"), destination: executableURL())
        linkResourceBundle(into: resources, projectRoot: projectRoot, fileManager: fileManager)
    }

    private static func writeInfoPlist(to url: URL) throws {
        let plist: [String: Any] = [
            "CFBundleExecutable": "Kaji",
            "CFBundleIdentifier": "com.kaji.swift-run",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Kaji",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.0.0",
            "CFBundleVersion": "0",
            "LSMinimumSystemVersion": "14.0",
            "NSPrincipalClass": "NSApplication",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func linkResourceBundle(into resources: URL, projectRoot _: URL, fileManager: FileManager) {
        let source = executableURL().deletingLastPathComponent().appendingPathComponent("Kaji_Kaji.bundle")
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? replaceLink(at: resources.appendingPathComponent("Kaji_Kaji.bundle"), destination: source)
    }

    private static func executableURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    }

    private static func replaceLink(at url: URL, destination: URL) throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    private static func launch(appURL: URL, projectRoot: URL, environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = openArguments(appURL: appURL, projectRoot: projectRoot, environment: environment)
        try process.run()
        process.waitUntilExit()
    }

    private static func openArguments(appURL: URL, projectRoot: URL, environment: [String: String]) -> [String] {
        var arguments = ["-n", "-W", "--env", "KAJI_SWIFT_RUN_BUNDLE=1"]
        for (key, value) in launchEnvironment(projectRoot: projectRoot, environment: environment) {
            arguments += ["--env", "\(key)=\(value)"]
        }
        arguments.append(appURL.path)
        return arguments
    }

    private static func launchEnvironment(projectRoot: URL, environment: [String: String]) -> [(String, String)] {
        [
            ("KAJI_PROJECT_ROOT", projectRoot.path),
            ("KAJI_APP_SUPPORT_DIR", environment["KAJI_APP_SUPPORT_DIR"]),
        ].compactMap { key, value in
            value.map { (key, $0) }
        }
    }
}
