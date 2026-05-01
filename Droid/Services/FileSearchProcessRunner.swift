import Foundation

enum FileSearchProcessRunner {
    struct Request {
        let executableURL: URL
        let arguments: [String]
        let projectPath: String
        let currentDirectoryPath: String?
        let limit: Int?
        let outputPathsAreRelative: Bool
    }

    static func collect(_ request: Request) async -> [FileSearchResult] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = request.executableURL
            process.arguments = request.arguments
            if let currentDirectoryPath = request.currentDirectoryPath {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            let parser = FileSearchResultParser(
                projectPath: request.projectPath,
                limit: request.limit,
                outputPathsAreRelative: request.outputPathsAreRelative
            )
            let handle = pipe.fileHandleForReading

            handle.readabilityHandler = { stream in
                let data = stream.availableData
                if data.isEmpty { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                if parser.append(chunk: chunk), process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { _ in
                handle.readabilityHandler = nil
                if let data = try? handle.readToEnd(), let chunk = String(data: data, encoding: .utf8) {
                    _ = parser.append(chunk: chunk)
                }
                continuation.resume(returning: parser.take())
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.resume(returning: [])
            }
        }
    }
}

private final class FileSearchResultParser: @unchecked Sendable {
    private let projectPath: String
    private let limit: Int?
    private let outputPathsAreRelative: Bool
    private let lock = NSLock()
    private var buffer = ""
    private var results: [FileSearchResult] = []

    init(projectPath: String, limit: Int?, outputPathsAreRelative: Bool) {
        self.projectPath = projectPath
        self.limit = limit
        self.outputPathsAreRelative = outputPathsAreRelative
    }

    func append(chunk: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let result = makeResult(from: line) {
                results.append(result)
                if let limit, results.count >= limit {
                    return true
                }
            }
        }

        return false
    }

    func take() -> [FileSearchResult] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }

    private func makeResult(from rawPath: String) -> FileSearchResult? {
        guard !rawPath.isEmpty else { return nil }
        let relativePath = outputPathsAreRelative ? rawPath : normalizeRelativePath(fromAbsolutePath: rawPath)
        let absolutePath = outputPathsAreRelative
            ? URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: projectPath)).path
            : rawPath
        let fileName = URL(fileURLWithPath: absolutePath).lastPathComponent
        return FileSearchResult(
            id: absolutePath,
            relativePath: relativePath,
            absolutePath: absolutePath,
            fileName: fileName
        )
    }

    private func normalizeRelativePath(fromAbsolutePath absolutePath: String) -> String {
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        if absolutePath.hasPrefix(prefix) {
            return String(absolutePath.dropFirst(prefix.count))
        }
        return absolutePath
    }
}
