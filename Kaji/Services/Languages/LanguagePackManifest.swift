import Foundation

struct LanguagePackManifest: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let extensions: [String]
    let filenames: [String]?
    let configuration: KajiLanguageConfiguration
    let syntax: LanguageSyntaxDefinition?
    let lsp: LanguageLSPDefinition?
    let snippets: [LanguageSnippet]?
    let formatter: LanguageFormatterDefinition?
}

extension LanguagePackManifest {
    func definition(source: LanguageDefinition.Source, rootURL: URL) -> LanguageDefinition {
        LanguageDefinition(
            id: id,
            name: name,
            extensions: extensions,
            filenames: filenames ?? [],
            configuration: configuration,
            syntax: syntax,
            lsp: lsp,
            snippets: snippets ?? [],
            formatter: formatter,
            source: source,
            rootPath: rootURL.path
        )
    }
}
