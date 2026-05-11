import Foundation
import Testing

@testable import Kaji

struct KajiFileStorageTests {
    @Test
    func appSupportDirectoryUsesEnvironmentOverride() throws {
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: override) }

        setenv("KAJI_APP_SUPPORT_DIR", override.path, 1)
        defer { unsetenv("KAJI_APP_SUPPORT_DIR") }

        let resolved = KajiFileStorage.appSupportDirectory()

        #expect(resolved.path == override.path)
        #expect(FileManager.default.fileExists(atPath: override.path))
    }
}
