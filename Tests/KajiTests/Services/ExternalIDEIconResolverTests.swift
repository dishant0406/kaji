import Foundation
import Testing

@testable import Kaji

struct ExternalIDEIconResolverTests {
    @Test
    func resolvesOnlyRealApplicationIconPaths() {
        let resolver = ExternalIDEFakeResolver(
            applications: [
                "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            ],
            executables: ["zed": "/usr/local/bin/zed"]
        )
        let catalog = ExternalIDECatalog(resolver: resolver)
        let iconResolver = ExternalIDEIconResolver(catalog: catalog)
        let vscode = ExternalIDECatalog.builtInIDEs.first { $0.id == "vscode" }!
        let zed = ExternalIDECatalog.builtInIDEs.first { $0.id == "zed" }!

        #expect(iconResolver.iconPath(for: vscode) == "/Applications/Visual Studio Code.app")
        #expect(iconResolver.iconPath(for: zed) == nil)
    }

    @Test
    func mapsInstalledIDEIDsToApplicationIconPaths() {
        let resolver = ExternalIDEFakeResolver(
            applications: [
                "com.example.Custom": URL(fileURLWithPath: "/Applications/Custom.app"),
            ],
            existingPaths: ["/Applications/Custom.app"]
        )
        let catalog = ExternalIDECatalog(resolver: resolver)
        let custom = ExternalIDECustomApplication(
            displayName: "Custom",
            bundleIdentifier: "com.example.Custom",
            appPath: "/Applications/Custom.app"
        )
        let ides = catalog.installedIDEs(customApplications: [custom])

        let iconPaths = ExternalIDEIconResolver(catalog: catalog).iconPaths(for: ides)

        #expect(iconPaths[custom.id] == "/Applications/Custom.app")
        #expect(iconPaths.count == 1)
    }
}
