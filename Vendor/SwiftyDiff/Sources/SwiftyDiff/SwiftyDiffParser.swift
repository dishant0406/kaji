import Foundation

public enum SwiftyDiffParser {
    public static func parse(_ output: String) -> [SwiftyDiffFile] {
        let lines = output.components(separatedBy: "\n")
        var files: [SwiftyDiffFile] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("diff --git") {
                let parsed = parseFile(lines: lines, startIndex: index)
                if let file = parsed.file {
                    files.append(file)
                }
                index = parsed.nextIndex
            } else {
                index += 1
            }
        }

        return files
    }

    public static func parseHunk(_ lines: [String], startIndex: Int) -> (hunk: SwiftyDiffHunk?, nextIndex: Int) {
        var index = startIndex
        let headerLine = lines[index]

        guard let header = HunkHeaderParser.parse(headerLine) else {
            return (nil, index + 1)
        }

        index += 1

        var diffLines: [SwiftyDiffLine] = []
        var oldLineNumber = header.oldStart
        var newLineNumber = header.newStart

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("@@") || line.hasPrefix("diff --git") {
                break
            }

            let parsed = parseLine(line, oldLineNumber: oldLineNumber, newLineNumber: newLineNumber)
            diffLines.append(parsed.line)
            oldLineNumber += parsed.oldIncrement
            newLineNumber += parsed.newIncrement
            index += 1
        }

        return (SwiftyDiffHunk(
            header: headerLine,
            oldStart: header.oldStart,
            oldCount: header.oldCount,
            newStart: header.newStart,
            newCount: header.newCount,
            lines: diffLines
        ), index)
    }

    private static func parseFile(lines: [String], startIndex: Int) -> (file: SwiftyDiffFile?, nextIndex: Int) {
        var index = startIndex
        var path = ""
        var oldPath: String?
        var status: SwiftyDiffFileStatus = .modified
        var hunks: [SwiftyDiffHunk] = []

        if index < lines.count, lines[index].hasPrefix("diff --git") {
            let paths = parseDiffHeaderPaths(lines[index])
            oldPath = paths.old
            path = paths.new
            index += 1
        }

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("diff --git") {
                break
            }

            if line.hasPrefix("new file mode") {
                status = .added
                index += 1
            } else if line.hasPrefix("deleted file mode") {
                status = .deleted
                index += 1
            } else if line.hasPrefix("rename from") {
                status = .renamed
                oldPath = String(line.dropFirst("rename from ".count))
                index += 1
            } else if line.hasPrefix("rename to") {
                path = String(line.dropFirst("rename to ".count))
                index += 1
            } else if line.hasPrefix("copy from") {
                status = .copied
                oldPath = String(line.dropFirst("copy from ".count))
                index += 1
            } else if line.hasPrefix("copy to") {
                path = String(line.dropFirst("copy to ".count))
                index += 1
            } else if line.hasPrefix("@@") {
                let parsed = parseHunk(lines, startIndex: index)
                if let hunk = parsed.hunk {
                    hunks.append(hunk)
                }
                index = parsed.nextIndex
            } else {
                index += 1
            }
        }

        guard !path.isEmpty else { return (nil, index) }

        return (SwiftyDiffFile(
            path: path,
            oldPath: oldPath != path ? oldPath : nil,
            status: status,
            hunks: hunks
        ), index)
    }

    private static func parseDiffHeaderPaths(_ line: String) -> (old: String?, new: String) {
        let components = line.components(separatedBy: " ")
        guard components.count >= 4 else { return (nil, "") }
        let oldPath = removeGitPrefix(components[2])
        return (oldPath, removeGitPrefix(components[3]))
    }

    private static func removeGitPrefix(_ path: String) -> String {
        guard path.count > 2 else { return path }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private static func parseLine(
        _ line: String,
        oldLineNumber: Int,
        newLineNumber: Int
    ) -> (line: SwiftyDiffLine, oldIncrement: Int, newIncrement: Int) {
        if line.hasPrefix("+") {
            return (SwiftyDiffLine(
                type: .addition,
                content: String(line.dropFirst()),
                oldLineNumber: nil,
                newLineNumber: newLineNumber
            ), 0, 1)
        }

        if line.hasPrefix("-") {
            return (SwiftyDiffLine(
                type: .deletion,
                content: String(line.dropFirst()),
                oldLineNumber: oldLineNumber,
                newLineNumber: nil
            ), 1, 0)
        }

        if line.hasPrefix(" ") {
            let content = String(line.dropFirst())
            return (SwiftyDiffLine(
                type: .context,
                content: content,
                oldLineNumber: oldLineNumber,
                newLineNumber: newLineNumber
            ), 1, 1)
        }

        return (SwiftyDiffLine(
            type: .context,
            content: line,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber
        ), 1, 1)
    }
}
