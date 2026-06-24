import Foundation

struct ExternalIDECatalog {
    let resolver: ExternalIDEApplicationResolving

    init(resolver: ExternalIDEApplicationResolving = ExternalIDEApplicationResolver()) {
        self.resolver = resolver
    }

    var installedIDEs: [ExternalIDE] {
        installedIDEs(customApplications: [])
    }

    func installedIDEs(customApplications: [ExternalIDECustomApplication]) -> [ExternalIDE] {
        let candidates = Self.builtInIDEs + customApplications.map(\.ide)
        var seen = Set<String>()
        return candidates.filter { ide in
            guard isInstalled(ide) else { return false }
            let key = resolvedApplicationURL(for: ide)?.path ?? ide.id
            return seen.insert(key).inserted
        }
    }

    func resolvedApplicationURL(for ide: ExternalIDE) -> URL? {
        for bundleIdentifier in ide.bundleIdentifiers {
            if let url = resolver.applicationURL(for: bundleIdentifier) {
                return url
            }
        }
        for path in ide.appPaths where resolver.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    func resolvedExecutablePath(for ide: ExternalIDE) -> String? {
        for executableName in ide.executableNames {
            if let path = resolver.fastExecutablePath(for: executableName) {
                return path
            }
        }
        return nil
    }

    func resolvedExecutablePathIncludingShell(for ide: ExternalIDE) async -> String? {
        if let path = resolvedExecutablePath(for: ide) {
            return path
        }
        for executableName in ide.executableNames {
            if let path = await resolver.shellExecutablePath(for: executableName) {
                return path
            }
        }
        return nil
    }

    private func isInstalled(_ ide: ExternalIDE) -> Bool {
        resolvedApplicationURL(for: ide) != nil
    }

    static let builtInIDEs: [ExternalIDE] = [
        .init(
            id: "vscode",
            displayName: "VS Code",
            bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
            executableNames: ["code", "code-insiders"],
            appPaths: [
                "/Applications/Visual Studio Code.app",
                "\(NSHomeDirectory())/Applications/Visual Studio Code.app",
                "/Applications/Visual Studio Code - Insiders.app",
            ]
        ),
        .init(
            id: "zed",
            displayName: "Zed",
            bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview"],
            executableNames: ["zed"],
            appPaths: ["/Applications/Zed.app", "\(NSHomeDirectory())/Applications/Zed.app"]
        ),
        .init(
            id: "cursor",
            displayName: "Cursor",
            bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"],
            executableNames: ["cursor"],
            appPaths: ["/Applications/Cursor.app", "\(NSHomeDirectory())/Applications/Cursor.app"]
        ),
        .init(
            id: "windsurf",
            displayName: "Windsurf",
            bundleIdentifiers: ["com.exafunction.windsurf"],
            executableNames: ["windsurf"],
            appPaths: ["/Applications/Windsurf.app", "\(NSHomeDirectory())/Applications/Windsurf.app"]
        ),
        .init(
            id: "intellij",
            displayName: "IntelliJ IDEA",
            bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"],
            executableNames: ["idea"],
            appPaths: ["/Applications/IntelliJ IDEA.app", "/Applications/IntelliJ IDEA CE.app"]
        ),
        .init(
            id: "webstorm",
            displayName: "WebStorm",
            bundleIdentifiers: ["com.jetbrains.WebStorm"],
            executableNames: ["webstorm"],
            appPaths: ["/Applications/WebStorm.app"]
        ),
        .init(
            id: "pycharm",
            displayName: "PyCharm",
            bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"],
            executableNames: ["pycharm"],
            appPaths: ["/Applications/PyCharm.app", "/Applications/PyCharm CE.app"]
        ),
        .init(
            id: "android-studio",
            displayName: "Android Studio",
            bundleIdentifiers: ["com.google.android.studio"],
            executableNames: ["studio"],
            appPaths: ["/Applications/Android Studio.app"]
        ),
        .init(
            id: "xcode",
            displayName: "Xcode",
            bundleIdentifiers: ["com.apple.dt.Xcode"],
            executableNames: ["xed"],
            appPaths: ["/Applications/Xcode.app"]
        ),
        .init(
            id: "sublime-text",
            displayName: "Sublime Text",
            bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"],
            executableNames: ["subl"],
            appPaths: ["/Applications/Sublime Text.app"]
        ),
    ]
}
