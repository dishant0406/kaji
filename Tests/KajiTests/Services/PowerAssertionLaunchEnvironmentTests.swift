import KajiPowerHelperProtocol
import Testing
import ServiceManagement

@testable import Kaji

struct PowerAssertionLaunchEnvironmentTests {
    @Test
    func verifiedAppAssertionMarksNativeChildOwnership() {
        let environment = PowerAssertionLaunchEnvironment.applyingAppOwnership(
            to: ["PATH": "/usr/bin"],
            assertionIsActive: true
        )

        #expect(environment[PowerAssertionLaunchEnvironment.ownershipKey] == "1")
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test
    func inactiveAppAssertionRemovesInheritedOwnershipClaim() {
        let environment = PowerAssertionLaunchEnvironment.applyingAppOwnership(
            to: [PowerAssertionLaunchEnvironment.ownershipKey: "1"],
            assertionIsActive: false
        )

        #expect(environment[PowerAssertionLaunchEnvironment.ownershipKey] == nil)
    }
}

@Suite("Power Protect response box")
struct PowerProtectResponseBoxTests {
    @Test
    func firstReplyWinsAndLateRepliesAreIgnored() async throws {
        let box = PowerProtectResponseBox<Int>()
        let value = try await box.wait(timeout: .seconds(1)) { complete in
            complete(.success(42))
            complete(.success(99))
        }

        #expect(value == 42)
    }

    @Test
    func missingReplyTimesOut() async {
        let box = PowerProtectResponseBox<Int>()

        await #expect(throws: PowerHelperError.connectionFailed) {
            try await box.wait(timeout: .milliseconds(10)) { _ in }
        }
    }
}

@MainActor
@Suite("Power Protect registration")
struct PowerProtectRegistrationTests {
    @Test
    func missingPackagedAssetsExplainWhyInstallationCannotRun() async throws {
        let service = RecordingPowerProtectService(status: .notRegistered)
        let bundle = try makeBundle(includeAssets: false)
        let manager = PowerProtectManager(service: service, bundle: bundle)

        await manager.register()

        #expect(service.registerCount == 0)
        #expect(manager.state == .failed("Power Protect requires a packaged Kaji app containing its signed helper."))
    }

    @Test
    func registrationFailureRemainsVisibleInsteadOfResettingToNotInstalled() async throws {
        let service = RecordingPowerProtectService(status: .notRegistered)
        service.registerError = PowerProtectRegistrationTestError.failed
        let manager = PowerProtectManager(service: service, bundle: try makeBundle(includeAssets: true))

        await manager.register()

        #expect(service.registerCount == 1)
        if case let .failed(message) = manager.state {
            #expect(message.contains("registration failed"))
        } else {
            Issue.record("Expected visible registration failure")
        }
    }

    private func makeBundle(includeAssets: Bool) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Kaji.app", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.kaji.test",
            "CFBundleExecutable": "Kaji",
            "CFBundlePackageType": "APPL",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        if includeAssets {
            let helper = contents.appendingPathComponent("MacOS/KajiPowerHelper")
            let daemon = contents.appendingPathComponent("Library/LaunchDaemons/com.kaji.app.power-helper.plist")
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: daemon.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            try Data().write(to: daemon)
        }
        return try #require(Bundle(url: root))
    }
}

private enum PowerProtectRegistrationTestError: LocalizedError {
    case failed
    var errorDescription: String? { "registration failed" }
}

@MainActor
private final class RecordingPowerProtectService: PowerProtectServiceManaging {
    var status: SMAppService.Status
    var registerError: Error?
    var registerCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
    }

    func unregister() async throws {}
}
