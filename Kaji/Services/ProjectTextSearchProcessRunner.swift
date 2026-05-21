import Foundation

enum ProjectTextSearchProcessRunner {
    struct Request {
        let executableURL: URL
        let arguments: [String]
        let projectPath: String
        let currentDirectoryPath: String
        let limit: Int
    }

    static func search(request: Request) async -> [ProjectTextSearchFileGroup] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = request.executableURL
            process.arguments = request.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: request.currentDirectoryPath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            let parser = ProjectTextSearchResultParser(projectPath: request.projectPath, limit: request.limit)
            let handle = pipe.fileHandleForReading
            let context = ProjectTextSearchRunContext(
                process: process,
                handle: handle,
                parser: parser,
                continuation: continuation
            )

            handle.readabilityHandler = { [context] stream in
                let data = stream.availableData
                if data.isEmpty { return }
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

private final class ProjectTextSearchRunContext: @unchecked Sendable {
    var process: Process?
    let parser: ProjectTextSearchResultParser
    private let continuation: CheckedContinuation<[ProjectTextSearchFileGroup], Never>
    private let lock = NSLock()
    private var handle: FileHandle?
    private var didComplete = false

    init(
        process: Process,
        handle: FileHandle,
        parser: ProjectTextSearchResultParser,
        continuation: CheckedContinuation<[ProjectTextSearchFileGroup], Never>
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
        complete(ProjectTextSearchService.group(parser.take()))
    }

    func complete(_ result: [ProjectTextSearchFileGroup]) {
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

final class ProjectTextSearchResultParser: @unchecked Sendable {
    private let projectPath: String
    private let limit: Int
    private let lock = NSLock()
    private var buffer = ""
    private var results: [ProjectTextSearchMatch] = []

    init(projectPath: String, limit: Int) {
        self.projectPath = projectPath
        self.limit = limit
    }

    func append(chunk: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let match = makeResult(from: line) {
                results.append(match)
                if results.count >= limit { return true }
            }
        }
        return false
    }

    func take() -> [ProjectTextSearchMatch] {
        lock.lock()
        defer { lock.unlock() }
        if let match = makeResult(from: buffer) {
            results.append(match)
            buffer = ""
        }
        return results
    }

    private func makeResult(from rawLine: String) -> ProjectTextSearchMatch? {
        guard !rawLine.isEmpty else { return nil }
        let parts = rawLine.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let line = Int(parts[1]),
              let column = Int(parts[2])
        else { return nil }
        let relativePath = String(parts[0])
        let filePath = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath).path
        let preview = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectTextSearchMatch(
            id: "\(filePath):\(line):\(column)",
            filePath: filePath,
            relativePath: relativePath,
            line: line,
            column: column,
            preview: preview
        )
    }
}
