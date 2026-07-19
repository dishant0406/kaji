import CryptoKit
import Foundation

enum MeetingTranscriptionProtocolVariant: String, Codable, CaseIterable, Hashable {
    case fluidAudioLocal
    case openAICompatible
    case azureOpenAI
    case deepgram
    case elevenLabsScribe
    case assemblyAIStreamingV3
}

enum MeetingTranscriptionModelDiscoveryKind: String, Codable, CaseIterable, Hashable {
    case localRegistry
    case openAIModels
    case deepgramModels
    case elevenLabsModels
    case manual
}

enum MeetingTranscriptionEndpointProfileSource: String, Codable, Hashable {
    case builtIn
    case custom
}

enum MeetingTranscriptionEndpointProfileError: Error, Equatable {
    case invalidProfile
    case invalidURL
    case invalidProvider
    case invalidProtocol
    case invalidDiscovery
    case endpointUnavailable
}

struct MeetingTranscriptionModelDiscoveryConfiguration: Codable, Hashable {
    let kind: MeetingTranscriptionModelDiscoveryKind
    let path: String?
    let projectID: String?

    init(kind: MeetingTranscriptionModelDiscoveryKind, path: String? = nil, projectID: String? = nil) throws {
        let normalizedPath = try path.map(Self.normalizedPath)
        let normalizedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedProjectID.map({ !$0.isEmpty && $0.utf8.count <= 200 && !$0.contains("\0") }) ?? true else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        switch kind {
        case .localRegistry,
             .manual:
            guard normalizedPath == nil, normalizedProjectID == nil else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
        case .openAIModels,
             .elevenLabsModels:
            guard normalizedPath != nil, normalizedProjectID == nil else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
        case .deepgramModels:
            guard normalizedPath != nil else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
        }
        self.kind = kind
        self.path = normalizedPath
        self.projectID = normalizedProjectID
    }

    private static func normalizedPath(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              trimmed.utf8.count <= 512,
              !trimmed.contains("\0"),
              !trimmed.contains("?"),
              !trimmed.contains("#"),
              !trimmed.split(separator: "/", omittingEmptySubsequences: true).contains("..")
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        return trimmed
    }
}

struct MeetingTranscriptionEndpointProfile: Codable, Hashable, Identifiable {
    let id: UUID
    let providerID: String
    let displayName: String
    let variant: MeetingTranscriptionProtocolVariant
    let regionID: String
    let restBaseURL: String?
    let webSocketBaseURL: String?
    let discovery: MeetingTranscriptionModelDiscoveryConfiguration
    let source: MeetingTranscriptionEndpointProfileSource

    init(
        id: UUID = UUID(),
        providerID: String,
        displayName: String,
        variant: MeetingTranscriptionProtocolVariant,
        regionID: String,
        restBaseURL: String?,
        webSocketBaseURL: String?,
        discovery: MeetingTranscriptionModelDiscoveryConfiguration,
        source: MeetingTranscriptionEndpointProfileSource
    ) throws {
        let providerID = try MeetingTranscriptionValidation.normalizedIdentifier(providerID, field: "endpoint.providerID")
        let regionID = try MeetingTranscriptionValidation.normalizedIdentifier(regionID, field: "endpoint.regionID")
        let displayName = try MeetingTranscriptionValidation.normalizedText(
            displayName,
            field: "endpoint.displayName",
            maximumLength: 120
        )
        let restBaseURL = try restBaseURL.map { try Self.normalizedBaseURL($0, schemes: ["https"]) }
        let webSocketBaseURL = try webSocketBaseURL.map { try Self.normalizedBaseURL($0, schemes: ["wss"]) }
        try Self.validateCompatibility(
            providerID: providerID,
            variant: variant,
            restBaseURL: restBaseURL,
            webSocketBaseURL: webSocketBaseURL,
            discovery: discovery
        )
        self.id = id
        self.providerID = providerID
        self.displayName = displayName
        self.variant = variant
        self.regionID = regionID
        self.restBaseURL = restBaseURL
        self.webSocketBaseURL = webSocketBaseURL
        self.discovery = discovery
        self.source = source
    }

    var snapshot: MeetingTranscriptionEndpointSnapshot {
        MeetingTranscriptionEndpointSnapshot(profile: self)
    }

    private static func normalizedBaseURL(_ value: String, schemes: Set<String>) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              schemes.contains(scheme),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedHost?.contains("%") == false,
              components.port.map({ 1 ... 65535 ~= $0 }) ?? true
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidURL
        }
        components.scheme = scheme
        components.host = host
        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path == "/" ? "" : path
        guard let normalized = components.url?.absoluteString, normalized.utf8.count <= 2048 else {
            throw MeetingTranscriptionEndpointProfileError.invalidURL
        }
        return normalized
    }

    private static func validateCompatibility(
        providerID: String,
        variant: MeetingTranscriptionProtocolVariant,
        restBaseURL: String?,
        webSocketBaseURL: String?,
        discovery: MeetingTranscriptionModelDiscoveryConfiguration
    ) throws {
        switch variant {
        case .fluidAudioLocal:
            guard providerID == FluidAudioMeetingTranscriptionProvider.providerID,
                  restBaseURL == nil,
                  webSocketBaseURL == nil,
                  discovery.kind == .localRegistry
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        case .openAICompatible:
            guard providerID == OpenAIMeetingTranscriptionProvider.providerID,
                  restBaseURL != nil,
                  webSocketBaseURL != nil,
                  discovery.kind == .openAIModels || discovery.kind == .manual
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        case .azureOpenAI:
            guard providerID == OpenAIMeetingTranscriptionProvider.providerID,
                  restBaseURL != nil,
                  discovery.kind == .manual
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        case .deepgram:
            guard providerID == DeepgramMeetingTranscriptionProvider.providerID,
                  restBaseURL != nil,
                  webSocketBaseURL != nil,
                  discovery.kind == .deepgramModels || discovery.kind == .manual
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        case .elevenLabsScribe:
            guard providerID == ElevenLabsScribeMeetingTranscriptionProvider.providerID,
                  restBaseURL != nil,
                  webSocketBaseURL != nil,
                  discovery.kind == .elevenLabsModels || discovery.kind == .manual
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        case .assemblyAIStreamingV3:
            guard providerID == AssemblyAIMeetingTranscriptionProvider.providerID,
                  webSocketBaseURL != nil,
                  discovery.kind == .manual
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProtocol
            }
        }
    }
}

struct MeetingTranscriptionEndpointSnapshot: Codable, Hashable {
    let profileID: UUID
    let providerID: String
    let displayName: String
    let variant: MeetingTranscriptionProtocolVariant
    let regionID: String
    let restBaseURL: String?
    let webSocketBaseURL: String?
    let discovery: MeetingTranscriptionModelDiscoveryConfiguration
    let source: MeetingTranscriptionEndpointProfileSource
    let originFingerprint: String

    init(profile: MeetingTranscriptionEndpointProfile) {
        profileID = profile.id
        providerID = profile.providerID
        displayName = profile.displayName
        variant = profile.variant
        regionID = profile.regionID
        restBaseURL = profile.restBaseURL
        webSocketBaseURL = profile.webSocketBaseURL
        discovery = profile.discovery
        source = profile.source
        originFingerprint = Self.fingerprint(
            providerID: profile.providerID,
            variant: profile.variant,
            restBaseURL: profile.restBaseURL,
            webSocketBaseURL: profile.webSocketBaseURL
        )
    }

    func restURL(path: String) throws -> URL {
        try Self.endpoint(base: restBaseURL, path: path, scheme: "https")
    }

    func webSocketURL(path: String) throws -> URL {
        try Self.endpoint(base: webSocketBaseURL, path: path, scheme: "wss")
    }

    func validate() throws {
        let profile = try MeetingTranscriptionEndpointProfile(
            id: profileID,
            providerID: providerID,
            displayName: displayName,
            variant: variant,
            regionID: regionID,
            restBaseURL: restBaseURL,
            webSocketBaseURL: webSocketBaseURL,
            discovery: discovery,
            source: source
        )
        guard profile.snapshot.originFingerprint == originFingerprint else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
    }

    private static func endpoint(base: String?, path: String, scheme: String) throws -> URL {
        guard let base,
              var components = URLComponents(string: base),
              components.scheme == scheme,
              let baseHost = components.host,
              path.hasPrefix("/"),
              !path.contains("?"),
              !path.contains("#"),
              !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidURL
        }
        let prefix = components.percentEncodedPath
        components.percentEncodedPath = prefix + path
        guard let url = components.url,
              url.host?.caseInsensitiveCompare(baseHost) == .orderedSame,
              url.scheme == scheme,
              url.user == nil,
              url.password == nil,
              url.fragment == nil
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidURL
        }
        return url
    }

    private static func fingerprint(
        providerID: String,
        variant: MeetingTranscriptionProtocolVariant,
        restBaseURL: String?,
        webSocketBaseURL: String?
    ) -> String {
        let payload = [providerID, variant.rawValue, restBaseURL ?? "", webSocketBaseURL ?? ""].joined(separator: "\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct MeetingTranscriptionEndpointRegistryDocument: Codable {
    let schemaVersion: Int
    let profiles: [MeetingTranscriptionEndpointProfile]

    init(schemaVersion: Int = 1, profiles: [MeetingTranscriptionEndpointProfile]) throws {
        guard schemaVersion == 1,
              profiles.count <= 64,
              Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map { "\($0.providerID)|\($0.regionID)" }).count == profiles.count
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }
}
