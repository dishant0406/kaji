import Foundation

enum CodingAgentShimInstaller {
    static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static func install(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        installBrowserMCP: Bool = false
    ) -> URL? {
        let directory = directory(homeDirectory: homeDirectory)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            for shim in CodingAgentShimScript.all {
                let url = directory.appendingPathComponent(shim.name)
                let data = Data(shim.content.utf8)
                if !fileManager.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) != data {
                    try data.write(to: url, options: .atomic)
                }
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            if installBrowserMCP {
                _ = try KajiBrowserMCPBinaryInstaller.install(homeDirectory: homeDirectory, fileManager: fileManager)
            }
            return directory
        } catch {
            return nil
        }
    }
}
