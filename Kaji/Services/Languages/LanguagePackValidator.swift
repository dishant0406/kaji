import Foundation

enum LanguagePackValidator {
    static func validateManifestData(_ data: Data, expectedSHA256: String?) throws -> LanguagePackManifest {
        guard LanguagePackIntegrity.matchesSHA256(data: data, expected: expectedSHA256) else {
            throw ValidationError.checksumMismatch
        }
        let manifest = try JSONDecoder().decode(LanguagePackManifest.self, from: data)
        try validate(manifest)
        return manifest
    }

    static func validate(_ manifest: LanguagePackManifest) throws {
        guard manifest.schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.missingID }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.missingName }
        guard !manifest.extensions.isEmpty || manifest.filenames?.isEmpty == false else { throw ValidationError.missingDetection }
        try validatePairs(manifest.configuration.brackets, field: "brackets")
        try validatePairs(manifest.configuration.autoClosingPairs, field: "autoClosingPairs")
        try validatePairs(manifest.configuration.surroundingPairs, field: "surroundingPairs")
        if let block = manifest.configuration.comments?.blockComment, block.count != 2 {
            throw ValidationError.invalidPair(field: "blockComment")
        }
        try validateRegex(manifest.configuration.indentationRules?.increaseIndentPattern)
        try validateRegex(manifest.configuration.indentationRules?.decreaseIndentPattern)
        try validateRegex(manifest.configuration.indentationRules?.indentNextLinePattern)
        try validateRegex(manifest.configuration.indentationRules?.unIndentedLinePattern)
        try validateRegex(manifest.configuration.folding?.markers?.start)
        try validateRegex(manifest.configuration.folding?.markers?.end)
    }

    private static func validatePairs(_ pairs: [[String]], field: String) throws {
        for pair in pairs where pair.count != 2 || pair[0].isEmpty || pair[1].isEmpty {
            throw ValidationError.invalidPair(field: field)
        }
    }

    private static func validateRegex(_ pattern: String?) throws {
        guard let pattern else { return }
        do {
            _ = try NSRegularExpression(pattern: pattern)
        } catch {
            throw ValidationError.invalidRegex(pattern: pattern)
        }
    }

    enum ValidationError: LocalizedError {
        case checksumMismatch
        case unsupportedSchema
        case missingID
        case missingName
        case missingDetection
        case invalidPair(field: String)
        case invalidRegex(pattern: String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                "Language pack checksum did not match the catalog."
            case .unsupportedSchema:
                "Language pack schema version is not supported."
            case .missingID:
                "Language pack is missing an id."
            case .missingName:
                "Language pack is missing a name."
            case .missingDetection:
                "Language pack must define at least one extension or filename."
            case let .invalidPair(field):
                "Language pack has an invalid pair in \(field)."
            case let .invalidRegex(pattern):
                "Language pack has an invalid regex: \(pattern)."
            }
        }
    }
}
