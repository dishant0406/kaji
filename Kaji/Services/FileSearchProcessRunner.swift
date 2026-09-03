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
            let context = FileSearchRunContext(
                process: process,
                handle: handle,
                parser: parser,
                continuation: continuation
            )

            handle.readabilityHandler = { [context] stream in
                let data = stream.availableData
                if data.isEmpty {
                    return
                }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                if context.parser.append(chunk: chunk), context.process?.isRunning == true {
                    context.process?.terminate()
                }
            }

            process.terminationHandler = { [context] _ in
                context.finish()
            }

            do {
                try process.run()
            } catch {
                context.complete([])
            }
        }
    }
}

private final class FileSearchRunContext: @unchecked Sendable {
    var process: Process?
    let parser: FileSearchResultParser
    private let continuation: CheckedContinuation<[FileSearchResult], Never>
    private let lock = NSLock()
    private var handle: FileHandle?
    private var didComplete = false

    init(
        process: Process,
        handle: FileHandle,
        parser: FileSearchResultParser,
        continuation: CheckedContinuation<[FileSearchResult], Never>
    ) {
        self.process = process
        self.handle = handle
        self.parser = parser
        self.continuation = continuation
    }

    func finish() {
        if let handle, let data = try? handle.readToEnd(), let chunk = String(data: data, encoding: .utf8) {
            _ = parser.append(chunk: chunk)
        }
        complete(parser.take())
    }

    func complete(_ result: [FileSearchResult]) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let handle = handle
        let process = process
        self.handle = nil
        self.process = nil
        lock.unlock()

        handle?.readabilityHandler = nil
        process?.terminationHandler = nil
        continuation.resume(returning: result)
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
