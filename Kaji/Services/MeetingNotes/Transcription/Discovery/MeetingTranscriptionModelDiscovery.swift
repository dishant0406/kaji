import Foundation
import Observation

enum MeetingTranscriptionModelCapabilityConfidence: String, Codable, Hashable {
    case providerReported
    case protocolAssumed
    case manual
}

struct MeetingDiscoveredTranscriptionModel: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let modes: Set<MeetingTranscriptionMode>
    let languageCodes: Set<String>
    let capabilityConfidence: MeetingTranscriptionModelCapabilityConfidence
    let metadata: [String: String]

    init(
        id: String,
        displayName: String,
        modes: Set<MeetingTranscriptionMode>,
        languageCodes: Set<String> = [],
        capabilityConfidence: MeetingTranscriptionModelCapabilityConfidence,
        metadata: [String: String] = [:]
    ) throws {
        self.id = try MeetingTranscriptionValidation.normalizedIdentifier(id, field: "discovery.model.id")
        self.displayName = try MeetingTranscriptionValidation.normalizedText(
            displayName,
            field: "discovery.model.displayName",
            maximumLength: 120
        )
        guard !modes.isEmpty,
              modes.count <= 3,
              languageCodes.count <= 256,
              languageCodes.allSatisfy(MeetingTranscriptionValidation.isValidLanguageCode)
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "discovery.model.metadata")
        self.modes = modes
        self.languageCodes = languageCodes
        self.capabilityConfidence = capabilityConfidence
        self.metadata = metadata
    }
}

struct MeetingTranscriptionModelCatalogSnapshot: Codable, Hashable, Identifiable {
    let endpointProfileID: UUID
    let credentialProfileID: UUID?
    let endpointFingerprint: String
    let fetchedAtMilliseconds: Int64
    let models: [MeetingDiscoveredTranscriptionModel]

    var id: String {
        "\(endpointProfileID.uuidString.lowercased())|\(credentialProfileID?.uuidString.lowercased() ?? "none")"
    }

    init(
        endpointProfileID: UUID,
        credentialProfileID: UUID?,
        endpointFingerprint: String,
        fetchedAtMilliseconds: Int64,
        models: [MeetingDiscoveredTranscriptionModel]
    ) throws {
        guard endpointFingerprint.count == 64,
              endpointFingerprint.allSatisfy(\.isHexDigit),
              fetchedAtMilliseconds >= 0,
              models.count <= 512,
              Set(models.map(\.id)).count == models.count
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        self.endpointProfileID = endpointProfileID
        self.credentialProfileID = credentialProfileID
        self.endpointFingerprint = endpointFingerprint
        self.fetchedAtMilliseconds = fetchedAtMilliseconds
        self.models = models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

enum MeetingTranscriptionModelDiscoveryState: Equatable {
    case idle
    case loading
    case loaded
    case stale(String)
    case failed(String)
}

protocol MeetingTranscriptionModelDiscovering: Sendable {
    func discover(
        endpoint: MeetingTranscriptionEndpointSnapshot,
        credentialProfileID: UUID?,
        credentialStore: any STTCredentialProfileStoring
    ) async throws -> [MeetingDiscoveredTranscriptionModel]
}

private final class MeetingModelDiscoveryRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor RemoteMeetingTranscriptionModelDiscovery: MeetingTranscriptionModelDiscovering {
    static let maximumResponseBytes = 4 * 1024 * 1024

    private let endpointValidator: any MeetingTranscriptionEndpointResolving
    private let session: URLSession

    init(
        endpointValidator: any MeetingTranscriptionEndpointResolving = MeetingTranscriptionEndpointResolutionValidator(),
        policy: STTURLSessionPolicy? = nil
    ) throws {
        self.endpointValidator = endpointValidator
        let resolvedPolicy = try policy ?? STTURLSessionPolicy(maximumResponseBytes: Self.maximumResponseBytes)
        session = URLSession(
            configuration: STTURLSessionConfigurationFactory.makeEphemeral(policy: resolvedPolicy),
            delegate: MeetingModelDiscoveryRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func discover(
        endpoint: MeetingTranscriptionEndpointSnapshot,
        credentialProfileID: UUID?,
        credentialStore: any STTCredentialProfileStoring
    ) async throws -> [MeetingDiscoveredTranscriptionModel] {
        try await endpointValidator.validate(endpoint)
        switch endpoint.discovery.kind {
        case .manual:
            return []
        case .localRegistry:
            return []
        case .openAIModels,
             .deepgramModels,
             .elevenLabsModels:
            guard let profileID = credentialProfileID else {
                throw MeetingTranscriptionProviderModuleError.credentialProfileRequired
            }
            var secret = try credentialStore.loadSecret(profileID: profileID)
            defer { secret.resetBytes(in: 0 ..< secret.count) }
            return try await discoverRemote(endpoint: endpoint, secret: secret)
        }
    }

    private func discoverRemote(
        endpoint: MeetingTranscriptionEndpointSnapshot,
        secret: Data
    ) async throws -> [MeetingDiscoveredTranscriptionModel] {
        guard let path = endpoint.discovery.path else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        let resolvedPath: String = if endpoint.discovery.kind == .deepgramModels, let projectID = endpoint.discovery.projectID {
            try "/v1/projects/\(encodedPathSegment(projectID))/models"
        } else {
            path
        }
        let url = try endpoint.restURL(path: resolvedPath)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try authorize(&request, kind: endpoint.discovery.kind, secret: secret)
        STTRequestSecurity.apply(to: &request)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url == url,
              response.statusCode == 200,
              response.expectedContentLength < 0 || response.expectedContentLength <= Int64(Self.maximumResponseBytes)
        else {
            throw MeetingTranscriptionEndpointProfileError.endpointUnavailable
        }
        var body = Data()
        body.reserveCapacity(min(Self.maximumResponseBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard body.count < Self.maximumResponseBytes else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
            body.append(byte)
        }
        switch endpoint.discovery.kind {
        case .openAIModels:
            return try Self.decodeOpenAI(body)
        case .deepgramModels:
            return try Self.decodeDeepgram(body)
        case .elevenLabsModels:
            return try Self.decodeElevenLabs(body)
        case .localRegistry,
             .manual:
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
    }

    private func authorize(
        _ request: inout URLRequest,
        kind: MeetingTranscriptionModelDiscoveryKind,
        secret: Data
    ) throws {
        guard !secret.isEmpty,
              secret.count <= 16 * 1024,
              let value = String(data: secret, encoding: .utf8),
              value.utf8.count == secret.count,
              value.utf8.allSatisfy({ 0x21 ... 0x7E ~= $0 })
        else {
            throw STTCredentialStoreError.invalidInput
        }
        switch kind {
        case .openAIModels:
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        case .deepgramModels:
            request.setValue("Token \(value)", forHTTPHeaderField: "Authorization")
        case .elevenLabsModels:
            request.setValue(value, forHTTPHeaderField: "xi-api-key")
        case .localRegistry,
             .manual:
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
    }

    private func encodedPathSegment(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))),
              !encoded.isEmpty
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        return encoded
    }

    static func decodeOpenAI(_ data: Data) throws -> [MeetingDiscoveredTranscriptionModel] {
        struct Response: Decodable {
            struct Model: Decodable {
                let id: String
                let ownedBy: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case ownedBy = "owned_by"
                }
            }

            let data: [Model]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try boundedUnique(response.data.map {
            try MeetingDiscoveredTranscriptionModel(
                id: $0.id,
                displayName: $0.id,
                modes: [.cloudBatch, .cloudRealtime],
                capabilityConfidence: .protocolAssumed,
                metadata: $0.ownedBy.map { ["owner": $0] } ?? [:]
            )
        })
    }

    static func decodeDeepgram(_ data: Data) throws -> [MeetingDiscoveredTranscriptionModel] {
        struct Response: Decodable {
            struct Model: Decodable {
                let name: String
                let canonicalName: String?
                let languages: [String]?
                let version: String?
                let uuid: String?
                let batch: Bool?
                let streaming: Bool?

                enum CodingKeys: String, CodingKey {
                    case name
                    case canonicalName = "canonical_name"
                    case languages
                    case version
                    case uuid
                    case batch
                    case streaming
                }
            }

            let stt: [Model]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try boundedUnique(response.stt.compactMap { value in
            let modes: Set<MeetingTranscriptionMode> = value.streaming == true ? [.cloudRealtime] : []
            guard !modes.isEmpty else { return nil }
            let languages = Set((value.languages ?? []).filter(MeetingTranscriptionValidation.isValidLanguageCode))
            var metadata: [String: String] = [:]
            if let version = value.version { metadata["version"] = version }
            if let uuid = value.uuid { metadata["uuid"] = uuid }
            if value.batch == true { metadata["batchAvailable"] = "true" }
            return try MeetingDiscoveredTranscriptionModel(
                id: value.name,
                displayName: value.canonicalName ?? value.name,
                modes: modes,
                languageCodes: languages,
                capabilityConfidence: .providerReported,
                metadata: metadata
            )
        })
    }

    static func decodeElevenLabs(_ data: Data) throws -> [MeetingDiscoveredTranscriptionModel] {
        struct Model: Decodable {
            struct Language: Decodable {
                let languageID: String

                enum CodingKeys: String, CodingKey {
                    case languageID = "language_id"
                }
            }

            let modelID: String
            let name: String?
            let languages: [Language]?

            enum CodingKeys: String, CodingKey {
                case modelID = "model_id"
                case name
                case languages
            }
        }
        let response = try JSONDecoder().decode([Model].self, from: data)
        return try boundedUnique(response.map {
            try MeetingDiscoveredTranscriptionModel(
                id: $0.modelID,
                displayName: $0.name ?? $0.modelID,
                modes: [.cloudBatch, .cloudRealtime],
                languageCodes: Set(($0.languages ?? []).map(\.languageID).filter(MeetingTranscriptionValidation.isValidLanguageCode)),
                capabilityConfidence: .protocolAssumed,
                metadata: ["sttCompatibility": "unverified"]
            )
        })
    }

    private static func boundedUnique(
        _ models: [MeetingDiscoveredTranscriptionModel]
    ) throws -> [MeetingDiscoveredTranscriptionModel] {
        guard models.count <= 512 else { throw MeetingTranscriptionEndpointProfileError.invalidDiscovery }
        let grouped = Dictionary(grouping: models, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        return models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
