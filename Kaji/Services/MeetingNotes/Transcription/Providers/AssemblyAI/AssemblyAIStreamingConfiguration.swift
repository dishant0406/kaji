import Foundation

enum AssemblyAIMeetingTranscriptionError: Error, Equatable {
    case invalidConfiguration
    case invalidCredential
    case credentialUnavailable
    case invalidRoute
    case invalidPacket
    case invalidState
    case malformedResponse
    case responseTooLarge
    case authenticationFailed
    case rateLimited
    case serviceUnavailable
    case timedOut
    case cancelled
}

enum AssemblyAIStreamingCredentialKind {
    case apiKey
    case temporaryToken
}

struct AssemblyAIStreamingCredential {
    let kind: AssemblyAIStreamingCredentialKind
    private let value: String

    init(apiKey: String) throws {
        kind = .apiKey
        value = try Self.validate(apiKey)
    }

    init(temporaryToken: String) throws {
        kind = .temporaryToken
        value = try Self.validate(temporaryToken)
    }

    func apply(to request: inout URLRequest) throws {
        switch kind {
        case .apiKey:
            request.setValue(value, forHTTPHeaderField: "Authorization")
        case .temporaryToken:
            guard let url = request.url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
            }
            var queryItems = components.queryItems ?? []
            guard !queryItems.contains(where: { $0.name == "token" }) else {
                throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
            }
            queryItems.append(URLQueryItem(name: "token", value: value))
            components.queryItems = queryItems.sorted { $0.name < $1.name }
            guard let authenticatedURL = components.url else {
                throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
            }
            request.url = authenticatedURL
        }
    }

    private static func validate(_ value: String) throws -> String {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.utf8.count <= 16 * 1024,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && scalar.value >= 0x21 && scalar.value <= 0x7E
              })
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidCredential
        }
        return value
    }
}

protocol AssemblyAISecretResolving: Sendable {
    func resolveCredential() async throws -> AssemblyAIStreamingCredential
}

struct AssemblyAISecretResolver: AssemblyAISecretResolving {
    private let resolver: @Sendable () async throws -> AssemblyAIStreamingCredential

    init(_ resolver: @escaping @Sendable () async throws -> AssemblyAIStreamingCredential) {
        self.resolver = resolver
    }

    func resolveCredential() async throws -> AssemblyAIStreamingCredential {
        try await resolver()
    }
}

struct AssemblyAIAccountPrivacyConfiguration {
    let trainingOptOutAttested: Bool

    init(trainingOptOutAttested: Bool = false) {
        self.trainingOptOutAttested = trainingOptOutAttested
    }

    static var providerDefault: Self {
        Self()
    }

    func validate(retention: MeetingTranscriptionDataRetentionClass) throws {
        switch retention {
        case .none:
            guard trainingOptOutAttested else {
                throw AssemblyAIMeetingTranscriptionError.invalidRoute
            }
        case .providerDefault,
             .configurable:
            break
        case .transient:
            throw AssemblyAIMeetingTranscriptionError.invalidRoute
        }
    }
}

struct AssemblyAIStreamingSessionConfiguration {
    static let sampleRateHertz = 16000
    static let channelCount = 1
    static let minimumAudioFrames = 800
    static let maximumAudioFrames = 16000
    static let maximumSessionSeconds = 10800

    let maximumSpeakers: Int?
    let prompt: String?
    let apiVersion: String?
    let privacy: AssemblyAIAccountPrivacyConfiguration
    let maximumInboundFrameBytes: Int
    let rotationWarningLeadSeconds: Int
    let beginTimeoutSeconds: TimeInterval
    let terminationTimeoutSeconds: TimeInterval

    init(
        maximumSpeakers: Int? = nil,
        prompt: String? = nil,
        apiVersion: String? = nil,
        privacy: AssemblyAIAccountPrivacyConfiguration = .providerDefault,
        maximumInboundFrameBytes: Int = 1024 * 1024,
        rotationWarningLeadSeconds: Int = 300,
        beginTimeoutSeconds: TimeInterval = 15,
        terminationTimeoutSeconds: TimeInterval = 10
    ) throws {
        guard maximumSpeakers.map({ 1 ... 10 ~= $0 }) ?? true,
              1024 ... 4 * 1024 * 1024 ~= maximumInboundFrameBytes,
              0 ... 3600 ~= rotationWarningLeadSeconds,
              beginTimeoutSeconds.isFinite,
              0.1 ... 60 ~= beginTimeoutSeconds,
              terminationTimeoutSeconds.isFinite,
              0.1 ... 60 ~= terminationTimeoutSeconds
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        self.maximumSpeakers = maximumSpeakers
        self.prompt = try prompt.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "assemblyAI.prompt", maximumLength: 1750)
        }
        self.apiVersion = try apiVersion.map(Self.validateAPIVersion)
        self.privacy = privacy
        self.maximumInboundFrameBytes = maximumInboundFrameBytes
        self.rotationWarningLeadSeconds = rotationWarningLeadSeconds
        self.beginTimeoutSeconds = beginTimeoutSeconds
        self.terminationTimeoutSeconds = terminationTimeoutSeconds
    }

    func makeRequest(
        route: MeetingTranscriptionRoute,
        context: MeetingTrackTranscriptionContextSnapshot,
        credential: AssemblyAIStreamingCredential,
        endpoint: URL
    ) throws -> URLRequest {
        guard context.canonicalSampleRateHertz == Self.sampleRateHertz,
              context.channelCount == Self.channelCount,
              context.keyterms.count <= 100,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "wss",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        var items = [
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "include_partial_turns", value: "true"),
            URLQueryItem(name: "sample_rate", value: String(Self.sampleRateHertz)),
            URLQueryItem(name: "speech_model", value: route.modelID),
        ]
        items.append(URLQueryItem(name: "language_detection", value: "true"))
        if !route.languageCodes.isEmpty {
            try items.append(URLQueryItem(name: "language_codes", value: Self.jsonString(route.languageCodes)))
        }
        if route.diarizationEnabled {
            items.append(URLQueryItem(name: "speaker_labels", value: "true"))
            if let maximumSpeakers {
                items.append(URLQueryItem(name: "max_speakers", value: String(maximumSpeakers)))
            }
        } else if maximumSpeakers != nil {
            throw AssemblyAIMeetingTranscriptionError.invalidRoute
        }
        if let prompt {
            items.append(URLQueryItem(name: "prompt", value: prompt))
        }
        if !context.keyterms.isEmpty {
            try items.append(URLQueryItem(name: "keyterms_prompt", value: Self.jsonString(context.keyterms)))
        }
        components.queryItems = items.sorted { $0.name < $1.name }
        guard let url = components.url,
              url.absoluteString.utf8.count <= 32 * 1024,
              url.scheme == "wss",
              url.host == endpoint.host,
              url.path == endpoint.path
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiVersion {
            request.setValue(apiVersion, forHTTPHeaderField: "AssemblyAI-Version")
        }
        try credential.apply(to: &request)
        return request
    }

    private static func jsonString(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        return value
    }

    private static func validateAPIVersion(_ value: String) throws -> String {
        guard value.count == 10,
              value.enumerated().allSatisfy({ index, character in
                  index == 4 || index == 7 ? character == "-" : character.isNumber
              })
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        return value
    }
}

struct AssemblyAIStreamingConfigurationUpdate: Encodable {
    let prompt: String?
    let keyterms: [String]?
    let languageCodes: [String]?

    init(prompt: String? = nil, keyterms: [String]? = nil, languageCodes: [String]? = nil) throws {
        guard prompt != nil || keyterms != nil || languageCodes != nil,
              keyterms.map({ $0.count <= 100 && Set($0).count == $0.count }) ?? true,
              languageCodes.map({
                  $0.count <= 18 && Set($0).count == $0.count && $0.allSatisfy(MeetingTranscriptionValidation.isValidLanguageCode)
              }) ?? true
        else {
            throw AssemblyAIMeetingTranscriptionError.invalidConfiguration
        }
        self.prompt = try prompt.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "assemblyAI.prompt", maximumLength: 1750)
        }
        self.keyterms = try keyterms?.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "assemblyAI.keyterm", maximumLength: 200)
        }
        self.languageCodes = languageCodes
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case prompt
        case keyterms = "keyterms_prompt"
        case languageCodes = "language_codes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("UpdateConfiguration", forKey: .type)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(keyterms, forKey: .keyterms)
        try container.encodeIfPresent(languageCodes, forKey: .languageCodes)
    }
}
