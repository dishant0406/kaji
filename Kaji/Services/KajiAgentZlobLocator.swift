import Foundation

enum KajiAgentZlobLocator {
    static func executableURL() -> URL? {
        let projectRoot = ProcessInfo.processInfo.environment["KAJI_PROJECT_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let candidates: [URL?] = [
            projectRoot?.appending(path: "Kaji/Resources/Zlob/zlob"),
            Bundle.appResources.url(forResource: "zlob", withExtension: nil, subdirectory: "Zlob"),
            Bundle.main.url(forResource: "zlob", withExtension: nil, subdirectory: "Zlob"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: "Kaji/Resources/Zlob/zlob"),
        ]
        for candidate in candidates.compactMap(\.self) {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if !FileManager.default.isExecutableFile(atPath: candidate.path) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
            }
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
