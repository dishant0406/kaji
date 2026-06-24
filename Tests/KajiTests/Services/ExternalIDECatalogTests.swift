import Foundation
import Testing

@testable import Kaji

struct ExternalIDECatalogTests {
    @Test
    func listsInstalledBuiltInAndCustomIDEs() {
        let resolver = ExternalIDEFakeResolver(
            applications: [
                "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                "com.example.Custom": URL(fileURLWithPath: "/Applications/Custom.app"),
            ],
            existingPaths: [
                "/Applications/Visual Studio Code.app",
                "/Applications/Custom.app",
            ]
        )
        let catalog = ExternalIDECatalog(resolver: resolver)
        let custom = ExternalIDECustomApplication(
            displayName: "Custom",
            bundleIdentifier: "com.example.Custom",
            appPath: "/Applications/Custom.app"
        )

        let ides = catalog.installedIDEs(customApplications: [custom])

        #expect(ides.map(\.displayName).contains("VS Code"))
        #expect(ides.map(\.displayName).contains("Custom"))
        #expect(!ides.map(\.displayName).contains("Zed"))
    }

    @Test
    func resolvesExecutablesWithoutListingCliOnlyIDEs() async {
        let resolver = ExternalIDEFakeResolver(executables: ["zed": "/usr/local/bin/zed"])
        let catalog = ExternalIDECatalog(resolver: resolver)
        let ide = ExternalIDECatalog.builtInIDEs.first { $0.id == "zed" }!

        let ides = catalog.installedIDEs(customApplications: [])

        #expect(!ides.map(\.id).contains("zed"))
        #expect(catalog.resolvedExecutablePath(for: ide) == "/usr/local/bin/zed")
        #expect(await catalog.resolvedExecutablePathIncludingShell(for: ide) == "/usr/local/bin/zed")
    }

    @Test
    func shellResolutionIsReservedForExplicitOpenFallbacks() async {
        let resolver = ExternalIDEFakeResolver(shellExecutables: ["zed": "/opt/homebrew/bin/zed"])
        let catalog = ExternalIDECatalog(resolver: resolver)
        let ide = ExternalIDECatalog.builtInIDEs.first { $0.id == "zed" }!

        let ides = catalog.installedIDEs(customApplications: [])

        #expect(!ides.map(\.id).contains("zed"))
        #expect(catalog.resolvedExecutablePath(for: ide) == nil)
        #expect(await catalog.resolvedExecutablePathIncludingShell(for: ide) == "/opt/homebrew/bin/zed")
    }

    @Test
    func removesDuplicateApplicationURLs() {
        let resolver = ExternalIDEFakeResolver(
            applications: ["com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Code.app")],
            existingPaths: ["/Applications/Code.app"]
        )
        let catalog = ExternalIDECatalog(resolver: resolver)
        let custom = ExternalIDECustomApplication(
            displayName: "Code Custom",
            bundleIdentifier: "com.microsoft.VSCode",
            appPath: "/Applications/Code.app"
        )

        let ides = catalog.installedIDEs(customApplications: [custom])

        #expect(ides.filter { $0.id == "vscode" || $0.id == custom.id }.count == 1)
    }
}

struct ExternalIDEFakeResolver: ExternalIDEApplicationResolving {
    var applications: [String: URL] = [:]
    var executables: [String: String] = [:]
    var shellExecutables: [String: String] = [:]
    var existingPaths: Set<String> = []

    func applicationURL(for bundleIdentifier: String) -> URL? {
        applications[bundleIdentifier]
    }

    func fastExecutablePath(for executableName: String) -> String? {
        executables[executableName]
    }

    func shellExecutablePath(for executableName: String) async -> String? {
        shellExecutables[executableName]
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }
}
