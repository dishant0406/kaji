import Foundation

enum GhosttyRuntimeResourceLocator {
    static func preferredResourceDirectory(
        bundleResourceURL: URL?,
        currentEnv: String?,
        externalCandidates: [String]
    ) -> String? {
        if let bundleResourceURL {
            let bundled = bundleResourceURL.appendingPathComponent("ghostty", isDirectory: true).path
            if hasRuntimeResources(at: bundled) {
                return bundled
            }
        }

        if let currentEnv, hasRuntimeResources(at: currentEnv) {
            return currentEnv
        }

        for path in externalCandidates where hasRuntimeResources(at: path) {
            return path
        }

        return nil
    }

    static func hasRuntimeResources(at path: String) -> Bool {
        let shellIntegrationPath = (path as NSString).appendingPathComponent("shell-integration")
        let terminfoPath = (path as NSString).appendingPathComponent("terminfo")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: shellIntegrationPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: terminfoPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
