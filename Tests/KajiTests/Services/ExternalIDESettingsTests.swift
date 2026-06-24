import Foundation
import Testing

@testable import Kaji

struct ExternalIDESettingsTests {
    @Test
    @MainActor
    func persistsSelectedIDEAndCustomApplications() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("external-ides.json")
        let appURL = try createApplicationBundle(
            in: directory,
            name: "Sample IDE",
            bundleIdentifier: "com.example.SampleIDE"
        )

        let first = ExternalIDESettings(fileURL: fileURL)
        let app = first.addCustomApplication(at: appURL)
        first.select(app.id)

        let second = ExternalIDESettings(fileURL: fileURL)

        #expect(second.selectedIDEID == app.id)
        #expect(second.customApplications.count == 1)
        #expect(second.customApplications[0].displayName == "Sample IDE")
        #expect(second.customApplications[0].bundleIdentifier == "com.example.SampleIDE")
    }

    @Test
    @MainActor
    func replacesExistingCustomApplicationByBundleID() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("external-ides.json")
        let firstApp = try createApplicationBundle(
            in: directory,
            name: "First Name",
            bundleIdentifier: "com.example.Editor"
        )
        let secondApp = try createApplicationBundle(
            in: directory,
            name: "Second Name",
            bundleIdentifier: "com.example.Editor"
        )

        let settings = ExternalIDESettings(fileURL: fileURL)
        settings.addCustomApplication(at: firstApp)
        settings.addCustomApplication(at: secondApp)

        #expect(settings.customApplications.count == 1)
        #expect(settings.customApplications[0].displayName == "Second Name")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createApplicationBundle(
        in directory: URL,
        name: String,
        bundleIdentifier: String
    ) throws -> URL {
        let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleName": name,
            "CFBundleIdentifier": bundleIdentifier,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }
}
