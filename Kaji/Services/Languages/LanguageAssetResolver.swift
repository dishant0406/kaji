import Foundation

enum LanguageAssetResolver {
    static func url(for relativePath: String?, in definition: LanguageDefinition) -> URL? {
        guard let relativePath, let rootPath = definition.rootPath else { return nil }
        return URL(fileURLWithPath: rootPath).appendingPathComponent(relativePath)
    }
}
