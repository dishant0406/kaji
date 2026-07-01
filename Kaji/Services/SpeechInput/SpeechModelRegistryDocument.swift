import Foundation

struct SpeechModelRegistryDocument: Codable, Equatable {
    let schemaVersion: Int
    let models: [SpeechInputModel]
}

enum SpeechModelRegistryError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case emptyCatalog
    case duplicateID(String)
    case invalidModel(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Speech model registry schema version \(version) is not supported."
        case .emptyCatalog:
            "Speech model registry must contain at least one model."
        case let .duplicateID(id):
            "Speech model registry has a duplicate model id: \(id)."
        case let .invalidModel(reason):
            "Speech model registry has an invalid model: \(reason)."
        }
    }
}

enum SpeechModelRegistryValidator {
    static let supportedSchemas = 1 ... 2

    static func validate(_ document: SpeechModelRegistryDocument) throws {
        guard supportedSchemas.contains(document.schemaVersion) else {
            throw SpeechModelRegistryError.unsupportedSchema(document.schemaVersion)
        }
        guard !document.models.isEmpty else { throw SpeechModelRegistryError.emptyCatalog }
        var seen = Set<String>()
        for model in document.models {
            try validate(model)
            guard seen.insert(model.id).inserted else { throw SpeechModelRegistryError.duplicateID(model.id) }
        }
    }

    private static func validate(_ model: SpeechInputModel) throws {
        try validateRequiredText(model)
        try validatePaths(model)
        try validateRuntime(model)
    }

    private static func validateRequiredText(_ model: SpeechInputModel) throws {
        guard !model.id.trimmedForSpeechRegistry.isEmpty else { throw SpeechModelRegistryError.invalidModel("id is empty") }
        guard !model.title.trimmedForSpeechRegistry.isEmpty
        else { throw SpeechModelRegistryError.invalidModel("title is empty for \(model.id)") }
        guard URL(string: model.registryBaseURL)?.scheme?.hasPrefix("http") == true else {
            throw SpeechModelRegistryError.invalidModel("registryBaseURL is invalid for \(model.id)")
        }
        guard !model.repo.trimmedForSpeechRegistry.isEmpty
        else { throw SpeechModelRegistryError.invalidModel("repo is empty for \(model.id)") }
        guard !model.revision.trimmedForSpeechRegistry.isEmpty
        else { throw SpeechModelRegistryError.invalidModel("revision is empty for \(model.id)") }
    }

    private static func validatePaths(_ model: SpeechInputModel) throws {
        guard model.cachePath.isSafeSpeechRegistryPath
        else { throw SpeechModelRegistryError.invalidModel("cachePath is unsafe for \(model.id)") }
        guard model.subPath?.isSafeSpeechRegistryPath != false
        else { throw SpeechModelRegistryError.invalidModel("subPath is unsafe for \(model.id)") }
        guard !model.requiredFiles.isEmpty else { throw SpeechModelRegistryError.invalidModel("requiredFiles is empty for \(model.id)") }
        guard model.requiredFiles.allSatisfy(\.isSafeSpeechRegistryPath) else {
            throw SpeechModelRegistryError.invalidModel("requiredFiles contains an unsafe path for \(model.id)")
        }
    }

    private static func validateRuntime(_ model: SpeechInputModel) throws {
        if model.engine == .fluidAudioParakeetEouStreaming, model.chunkSize == nil {
            throw SpeechModelRegistryError.invalidModel("chunkSize is required for \(model.id)")
        }
        if model.engine == .fluidAudioParakeetTdt, model.runtime?.asrVersion == nil {
            throw SpeechModelRegistryError.invalidModel("runtime.asrVersion is required for \(model.id)")
        }
    }
}

private extension String {
    var trimmedForSpeechRegistry: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSafeSpeechRegistryPath: Bool {
        let value = trimmedForSpeechRegistry
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("..") else { return false }
        return !value.split(separator: "/").contains { $0 == "." || $0.isEmpty }
    }
}
