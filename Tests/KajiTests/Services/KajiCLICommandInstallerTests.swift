import Foundation
import Testing

@testable import Kaji

@Suite("Kaji CLI command installer")
struct KajiCLICommandInstallerTests {
    @Test("install writes command and global symlink")
    func installWritesCommandAndLink() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }

        let result = KajiCLICommandInstaller.install(
            homeDirectory: fixture.home,
            linkURL: fixture.link,
            privilegedInstall: { _, _ in false }
        )

        #expect(result.state == .installed)
        #expect(KajiCLICommandInstaller.state(homeDirectory: fixture.home, linkURL: fixture.link) == .installed)
        #expect((try? String(contentsOf: KajiCLICommandInstaller.commandURL(homeDirectory: fixture.home), encoding: .utf8)) == KajiCLICommandScriptFactory.script())
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: fixture.link.path)) != nil)
    }

    @Test("existing unmanaged command is not overwritten")
    func existingUnmanagedCommandIsNotOverwritten() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "other".write(to: fixture.link, atomically: true, encoding: .utf8)

        let result = KajiCLICommandInstaller.install(
            homeDirectory: fixture.home,
            linkURL: fixture.link,
            privilegedInstall: { _, _ in false }
        )

        guard case .needsRepair = result.state else {
            Issue.record("Expected needsRepair, got \(result.state)")
            return
        }
        #expect((try? String(contentsOf: fixture.link, encoding: .utf8)) == "other")
    }

    @Test("uninstall removes managed command and link")
    func uninstallRemovesManagedFiles() throws {
        let fixture = try InstallerFixture()
        defer { fixture.cleanup() }
        _ = KajiCLICommandInstaller.install(homeDirectory: fixture.home, linkURL: fixture.link, privilegedInstall: { _, _ in false })

        let result = KajiCLICommandInstaller.uninstall(
            homeDirectory: fixture.home,
            linkURL: fixture.link,
            privilegedRemove: { _ in false }
        )

        #expect(result.state == .missing)
        #expect(!FileManager.default.fileExists(atPath: fixture.link.path))
        #expect(!FileManager.default.fileExists(atPath: KajiCLICommandInstaller.commandURL(homeDirectory: fixture.home).path))
    }
}

private final class InstallerFixture {
    let root: URL
    let home: URL
    let link: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kaji-cli-installer-\(UUID().uuidString)")
        home = root.appendingPathComponent("home", isDirectory: true)
        link = root.appendingPathComponent("usr/local/bin/kaji")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
