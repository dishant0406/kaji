import Foundation

enum LanguagePackNativeParserValidator {
    static func validatedParserURL(for definition: LanguageDefinition) -> URL? {
        guard let parser = definition.syntax?.treeSitter?.parser,
              let artifact = parser.artifact,
              let expectedSHA256 = parser.sha256,
              !expectedSHA256.isEmpty,
              let url = LanguageAssetResolver.url(for: artifact, in: definition),
              let data = try? Data(contentsOf: url),
              LanguagePackIntegrity.matchesSHA256(data: data, expected: expectedSHA256)
        else { return nil }
        return url
    }
}
