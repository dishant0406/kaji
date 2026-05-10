import Foundation

enum SwiftRunBundleLauncher {
    static func relaunchIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        guard environment["DROID_SWIFT_RUN_BUNDLE"] != "1" else { return }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        guard let projectRoot = projectRoot(fileManager: fileManager) else { return }
        let appURL = projectRoot.appendingPathComponent(".build/DroidSwiftRun.app", isDirectory: true)
        do {
            try prepareBundle(appURL: appURL, projectRoot: projectRoot, fileManager: fileManager)
            try launch(appURL: appURL, projectRoot: projectRoot, environment: environment)
            Darwin.exit(0)
        } catch {
            fputs("Droid failed to launch app bundle: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func projectRoot(fileManager: FileManager) -> URL? {
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        if fileManager.fileExists(atPath: current.appendingPathComponent("Droid/Info.plist").path) {
            return current
        }
        var cursor = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        while cursor.path != "/" {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent("Droid/Info.plist").path) {
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
        let frameworks = contents.appendingPathComponent("Frameworks", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try writeInfoPlist(to: contents.appendingPathComponent("Info.plist"))
        try replaceLink(at: macOS.appendingPathComponent("Droid"), destination: executableURL())
        linkResourceBundle(into: resources, projectRoot: projectRoot, fileManager: fileManager)
        linkCEF(into: frameworks, projectRoot: projectRoot, fileManager: fileManager)
    }

    private static func writeInfoPlist(to url: URL) throws {
        let plist: [String: Any] = [
            "CFBundleExecutable": "Droid",
            "CFBundleIdentifier": "com.droid.swift-run",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Droid",
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
        let source = executableURL().deletingLastPathComponent().appendingPathComponent("Droid_Droid.bundle")
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? replaceLink(at: resources.appendingPathComponent("Droid_Droid.bundle"), destination: source)
    }

    private static func linkCEF(into frameworks: URL, projectRoot: URL, fileManager: FileManager) {
        let release = projectRoot.appendingPathComponent(".dev-support/cef-runtime/build/tests/cefsimple/Release")
        let entries = (try? fileManager.contentsOfDirectory(at: release, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.pathExtension == "app" || entry.pathExtension == "framework" {
            try? replaceLink(at: frameworks.appendingPathComponent(entry.lastPathComponent), destination: entry)
        }
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
        var arguments = ["-n", "-W", "--env", "DROID_SWIFT_RUN_BUNDLE=1"]
        for (key, value) in launchEnvironment(projectRoot: projectRoot, environment: environment) {
            arguments += ["--env", "\(key)=\(value)"]
        }
        arguments.append(appURL.path)
        return arguments
    }

    private static func launchEnvironment(projectRoot: URL, environment: [String: String]) -> [(String, String)] {
        let cefRoot = projectRoot.appendingPathComponent(".dev-support/cef-runtime/cef_binary")
        let helper = projectRoot
            .appendingPathComponent(".dev-support/cef-runtime/build/tests/cefsimple/Release")
            .appendingPathComponent("cefsimple Helper.app/Contents/MacOS/cefsimple Helper")
        let profile = projectRoot.appendingPathComponent(".build/DroidSwiftRunCEFProfile", isDirectory: true)
        return [
            ("DROID_APP_SUPPORT_DIR", environment["DROID_APP_SUPPORT_DIR"]),
            ("DROID_CEF_ROOT", environment["DROID_CEF_ROOT"] ?? cefRoot.path),
            ("DROID_CEF_HELPER_PATH", environment["DROID_CEF_HELPER_PATH"] ?? helper.path),
            ("DROID_CEF_PROFILE_PATH", environment["DROID_CEF_PROFILE_PATH"] ?? profile.path),
        ].compactMap { key, value in
            value.map { (key, $0) }
        }
    }
}
