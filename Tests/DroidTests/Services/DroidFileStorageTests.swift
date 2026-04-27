import Foundation
import Testing

@testable import Droid

struct DroidFileStorageTests {
    @Test
    func appSupportDirectoryUsesEnvironmentOverride() throws {
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: override) }

        setenv("DROID_APP_SUPPORT_DIR", override.path, 1)
        defer { unsetenv("DROID_APP_SUPPORT_DIR") }

        let resolved = DroidFileStorage.appSupportDirectory()

        #expect(resolved.path == override.path)
        #expect(FileManager.default.fileExists(atPath: override.path))
    }
}
