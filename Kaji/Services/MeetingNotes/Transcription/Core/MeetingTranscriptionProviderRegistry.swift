import Foundation

enum MeetingTranscriptionProviderRegistryError: Error, Equatable {
    case duplicateProvider(String)
    case providerNotFound(String)
    case invalidDescriptor(String)
}

actor MeetingTranscriptionProviderRegistry {
    private var providers: [String: any MeetingTranscriptionProvider] = [:]

    init(providers: [any MeetingTranscriptionProvider] = []) throws {
        for provider in providers {
            let id = provider.descriptor.id
            guard self.providers[id] == nil else {
                throw MeetingTranscriptionProviderRegistryError.duplicateProvider(id)
            }
            self.providers[id] = provider
        }
    }

    func register(_ provider: any MeetingTranscriptionProvider) throws {
        let id = provider.descriptor.id
        guard providers[id] == nil else {
            throw MeetingTranscriptionProviderRegistryError.duplicateProvider(id)
        }
        providers[id] = provider
    }

    func provider(id: String) throws -> any MeetingTranscriptionProvider {
        guard let provider = providers[id] else {
            throw MeetingTranscriptionProviderRegistryError.providerNotFound(id)
        }
        return provider
    }

    func descriptors() -> [MeetingTranscriptionProviderDescriptor] {
        providers.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    func validate(_ route: MeetingTranscriptionRoute) throws {
        guard let provider = providers[route.providerID] else {
            throw MeetingTranscriptionProviderRegistryError.providerNotFound(route.providerID)
        }
        try route.validate(against: provider.descriptor)
        for fallback in route.fallbacks {
            guard let fallbackProvider = providers[fallback.providerID],
                  let model = fallbackProvider.descriptor.model(id: fallback.modelID),
                  model.capabilities.modes.contains(fallback.mode),
                  model.regions.contains(where: { $0.id == fallback.regionID }),
                  model.privacy.supportedRetention.contains(route.retention),
                  route.languageCodes.allSatisfy({
                      model.supportedLanguageCodes.isEmpty || model.supportedLanguageCodes.contains($0)
                  }),
                  !route.diarizationEnabled || model.capabilities.diarization.availability != .unsupported
            else {
                throw MeetingTranscriptionProviderRegistryError.invalidDescriptor(fallback.providerID)
            }
        }
    }
}
