import FFFKit
import Foundation

enum FFFSearchResultMapper {
    static func fileResults(from result: UnsafePointer<FffSearchResult>, projectPath: String) -> [FileSearchResult] {
        guard let items = result.pointee.items else { return [] }
        return (0 ..< Int(result.pointee.count)).map { index in
            let item = items.advanced(by: index).pointee
            let relativePath = String(cString: item.relative_path)
            let fileName = String(cString: item.file_name)
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath).path
            return FileSearchResult(id: absolutePath, relativePath: relativePath, absolutePath: absolutePath, fileName: fileName)
        }
    }

    static func textMatches(from result: UnsafePointer<FffGrepResult>, projectPath: String) -> [ProjectTextSearchMatch] {
        guard let items = result.pointee.items else { return [] }
        return (0 ..< Int(result.pointee.count)).map { index in
            let item = items.advanced(by: index).pointee
            let relativePath = String(cString: item.relative_path)
            let lineContent = String(cString: item.line_content)
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath).path
            let column = Int(item.col) + 1
            return ProjectTextSearchMatch(
                id: "\(absolutePath):\(item.line_number):\(column)",
                filePath: absolutePath,
                relativePath: relativePath,
                line: Int(item.line_number),
                column: column,
                preview: lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
