import Foundation

enum RiftBinaryLocator {
    private static let overrideKey = "KAJI_RIFT_BINARY_PATH"

    static func url() -> URL? {
        if let override = ProcessInfo.processInfo.environment[overrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty,
            FileManager.default.isExecutableFile(atPath: override)
        {
            return URL(fileURLWithPath: override)
        }

        if let bundled = Bundle.appResources.url(forResource: "rift", withExtension: nil, subdirectory: "Rift"),
           FileManager.default.isExecutableFile(atPath: bundled.path)
        {
            return bundled
        }

        let candidates = [
            "Kaji/Resources/Rift/rift",
            ".build/debug/Kaji_Kaji.resources/Rift/rift",
            ".build/release/Kaji_Kaji.resources/Rift/rift",
        ]
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return candidates
            .map { root.appendingPathComponent($0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
