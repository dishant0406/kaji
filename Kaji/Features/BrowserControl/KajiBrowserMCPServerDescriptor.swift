import Foundation

struct KajiBrowserMCPServerDescriptor: Equatable {
    let name: String
    let command: String
    let arguments: [String]
    let environment: [String: String]

    static func current(
        environment: [String: String],
        fileManager: FileManager = .default,
        projectRoot: URL? = nil
    ) -> KajiBrowserMCPServerDescriptor? {
        guard let script = KajiBrowserMCPResourceLocator.scriptPath(fileManager: fileManager, projectRoot: projectRoot) else {
            return nil
        }
        return KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: "node",
            arguments: [script],
            environment: environment.filter { key, _ in key.hasPrefix("KAJI_BROWSER_") }
        )
    }
}
