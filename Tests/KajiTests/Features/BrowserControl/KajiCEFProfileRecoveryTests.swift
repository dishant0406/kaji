import Foundation
import Testing

@testable import Kaji

struct KajiCEFProfileRecoveryTests {
    @Test
    func removesStaleSingletonFilesAndWritesMarker() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeProfileFile("SingletonLock")
        try fixture.writeProfileFile("SingletonSocket")
        try fixture.writeProfileFile("SingletonCookie")
        try fixture.writeProfileFile("Default/Preferences")

        let profileURL = try KajiCEFProfileRecovery.prepareProfile(at: fixture.profileURL)

        #expect(profileURL == fixture.profileURL)
        #expect(!fixture.exists("SingletonLock"))
        #expect(!fixture.exists("SingletonSocket"))
        #expect(!fixture.exists("SingletonCookie"))
        #expect(fixture.exists("Default/Preferences"))
        #expect(fixture.exists(".kaji-cef-starting"))
    }

    @Test
    func markStartedRemovesMarker() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let profileURL = try KajiCEFProfileRecovery.prepareProfile(at: fixture.profileURL)
        KajiCEFProfileRecovery.markStarted(profileURL: profileURL)

        #expect(!fixture.exists(".kaji-cef-starting"))
    }

    @Test
    func quarantinesProfileWhenPreviousStartupMarkerExists() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.writeProfileFile(".kaji-cef-starting")
        try fixture.writeProfileFile("Default/Preferences")

        let profileURL = try KajiCEFProfileRecovery.prepareProfile(at: fixture.profileURL)

        #expect(profileURL == fixture.profileURL)
        #expect(fixture.exists(".kaji-cef-starting"))
        #expect(!fixture.exists("Default/Preferences"))
        #expect(try fixture.quarantineDirectories().count == 1)
    }
}

private final class Fixture {
    let rootURL: URL
    let profileURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        profileURL = rootURL.appendingPathComponent("CEFProfile", isDirectory: true)
        try fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }

    func writeProfileFile(_ path: String) throws {
        let url = profileURL.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: url)
    }

    func exists(_ path: String) -> Bool {
        fileManager.fileExists(atPath: profileURL.appendingPathComponent(path).path)
    }

    func quarantineDirectories() throws -> [URL] {
        try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("CEFProfile.quarantined-") }
    }
}
