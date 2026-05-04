import Foundation

enum DroidKitDirectory {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".droidkit", isDirectory: true)
    }

    static var scriptsFile: URL {
        root.appendingPathComponent("scripts.json")
    }

    static var runs: URL {
        root.appendingPathComponent("runs", isDirectory: true)
    }

    static func ensure() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
    }
}
