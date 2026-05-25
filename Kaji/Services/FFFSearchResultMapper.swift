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

    static func fileResults(from response: FFFFileSearchResponse, projectPath: String) -> [FileSearchResult] {
        response.value.items.map { item in
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(item.relativePath).path
            return FileSearchResult(
                id: absolutePath,
                relativePath: item.relativePath,
                absolutePath: absolutePath,
                fileName: item.fileName
            )
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

    static func textMatches(from response: FFFGrepSearchResponse, projectPath: String) -> [ProjectTextSearchMatch] {
        response.value.items.map { item in
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(item.relativePath).path
            let column = Int(item.col) + 1
            return ProjectTextSearchMatch(
                id: "\(absolutePath):\(item.lineNumber):\(column)",
                filePath: absolutePath,
                relativePath: item.relativePath,
                line: Int(item.lineNumber),
                column: column,
                preview: item.lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

struct FFFFileSearchResponse: Decodable {
    let ok: Bool
    let value: FFFFileSearchValue
}

struct FFFFileSearchValue: Decodable {
    let items: [FFFFileItem]
}

struct FFFFileItem: Decodable {
    let relativePath: String
    let fileName: String
}

struct FFFGrepSearchResponse: Decodable {
    let ok: Bool
    let value: FFFGrepSearchValue
}

struct FFFGrepSearchValue: Decodable {
    let items: [FFFGrepItem]
}

struct FFFGrepItem: Decodable {
    let relativePath: String
    let lineContent: String
    let lineNumber: UInt64
    let col: UInt32
}
