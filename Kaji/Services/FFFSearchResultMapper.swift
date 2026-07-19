import FFFWorkerProtocol
import Foundation

enum FFFSearchResultMapper {
    static func fileResults(from results: [FFFWorkerFileResult], projectPath: String) -> [FileSearchResult] {
        results.map { result in
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(result.relativePath).path
            return FileSearchResult(
                id: absolutePath,
                relativePath: result.relativePath,
                absolutePath: absolutePath,
                fileName: result.fileName
            )
        }
    }

    static func textMatches(from results: [FFFWorkerTextMatch], projectPath: String) -> [ProjectTextSearchMatch] {
        results.map { result in
            let absolutePath = URL(fileURLWithPath: projectPath).appendingPathComponent(result.relativePath).path
            let column = Int(result.column) + 1
            return ProjectTextSearchMatch(
                id: "\(absolutePath):\(result.lineNumber):\(column)",
                filePath: absolutePath,
                relativePath: result.relativePath,
                line: Int(result.lineNumber),
                column: column,
                preview: ProjectTextSearchService.previewText(from: result.lineContent, column: column)
            )
        }
    }
}
