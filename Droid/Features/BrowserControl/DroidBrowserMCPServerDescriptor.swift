import Foundation

struct DroidBrowserMCPServerDescriptor: Equatable {
    let name: String
    let command: String
    let arguments: [String]
    let environment: [String: String]

    static func current(
        environment: [String: String],
        fileManager: FileManager = .default,
        projectRoot: URL? = nil
    ) -> DroidBrowserMCPServerDescriptor? {
        guard let script = DroidBrowserMCPResourceLocator.scriptPath(fileManager: fileManager, projectRoot: projectRoot) else {
            return nil
        }
        return DroidBrowserMCPServerDescriptor(
            name: "droid-browser",
            command: "node",
            arguments: [script],
            environment: environment.filter { key, _ in key.hasPrefix("DROID_BROWSER_") }
        )
    }
}
