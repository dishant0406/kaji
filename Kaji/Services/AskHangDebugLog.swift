import Foundation

enum AskHangDebugLog {
    static var path: String {
        fileURL.path
    }

    static func mark(_ event: String, _ details: [String: String] = [:]) {
        let line = ([timestamp(), event] + details.map { "\($0.key)=\($0.value)" }.sorted()).joined(separator: " | ") + "\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static let queue = DispatchQueue(label: "app.kaji.ask-hang-debug-log")

    private static var fileURL: URL {
        KajiFileStorage.fileURL(filename: "ask-hang-debug.log")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
