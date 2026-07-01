import Foundation

enum GitIgnoreChecker {
    static func ignoredPathsSync(
        repoPath: String,
        relativePaths: [String],
        timeout: DispatchTimeInterval = .seconds(5)
    ) -> Set<String>? {
        let paths = relativePaths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return [] }
        guard let gitPath = GitProcessRunner.resolveExecutable("git") else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", repoPath, "check-ignore", "-z", "--stdin"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        stdinPipe.fileHandleForWriting.write(payload(for: paths))
        try? stdinPipe.fileHandleForWriting.close()

        let output = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        _ = try? stderrPipe.fileHandleForReading.readToEnd()
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return nil }
        return Set(parseNullSeparated(output))
    }

    private static func payload(for paths: [String]) -> Data {
        var data = Data()
        for path in paths {
            guard let encoded = path.data(using: .utf8) else { continue }
            data.append(encoded)
            data.append(0)
        }
        return data
    }

    static func parseNullSeparated(_ data: Data) -> [String] {
        var values: [String] = []
        var current = Data()
        for byte in data {
            if byte == 0 {
                if let value = String(data: current, encoding: .utf8), !value.isEmpty {
                    values.append(value)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if let value = String(data: current, encoding: .utf8), !value.isEmpty {
            values.append(value)
        }
        return values
    }
}
