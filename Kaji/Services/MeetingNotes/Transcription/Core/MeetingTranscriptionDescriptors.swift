import Foundation

enum MeetingTranscriptionValidationError: Error, Equatable {
    case emptyValue(String)
    case valueTooLong(String)
    case invalidValue(String)
    case duplicateValue(String)
    case unsupportedValue(String)
    case invalidCapability(String)
    case invalidRoute(String)
    case invalidAudioPacket(String)
    case invalidEvent(String)
    case invalidEndpoint(String)
    case invalidBudget(String)
}

enum MeetingTranscriptionMode: String, Codable, CaseIterable, Hashable {
    case localChunked
    case cloudBatch
    case cloudRealtime
}

enum MeetingTranscriptionAudioEncoding: String, Codable, CaseIterable, Hashable {
    case pcmSigned16LittleEndian
    case pcmFloat32LittleEndian
    case wav
    case flac
    case caf
    case m4a
    case opus
    case webM

    var bytesPerPCMFramePerChannel: Int? {
        switch self {
        case .pcmSigned16LittleEndian:
            2
        case .pcmFloat32LittleEndian:
            4
        case .wav,
             .flac,
             .caf,
             .m4a,
             .opus,
             .webM:
            nil
        }
    }
}

struct MeetingTranscriptionInputFormat: Codable, Hashable {
    let encoding: MeetingTranscriptionAudioEncoding
    let sampleRatesHertz: [Int]
    let channelCounts: [Int]

    init(
        encoding: MeetingTranscriptionAudioEncoding,
        sampleRatesHertz: [Int],
        channelCounts: [Int]
    ) throws {
        guard !sampleRatesHertz.isEmpty,
              sampleRatesHertz.count <= 32,
              sampleRatesHertz.allSatisfy({ 8000 ... 384_000 ~= $0 }),
              Set(sampleRatesHertz).count == sampleRatesHertz.count
        else {
            throw MeetingTranscriptionValidationError.invalidValue("sampleRatesHertz")
        }
        guard !channelCounts.isEmpty,
              channelCounts.count <= 32,
              channelCounts.allSatisfy({ 1 ... 32 ~= $0 }),
              Set(channelCounts).count == channelCounts.count
        else {
            throw MeetingTranscriptionValidationError.invalidValue("channelCounts")
        }
        self.encoding = encoding
        self.sampleRatesHertz = sampleRatesHertz.sorted()
        self.channelCounts = channelCounts.sorted()
    }

    func supports(sampleRateHertz: Int, channelCount: Int) -> Bool {
        sampleRatesHertz.contains(sampleRateHertz) && channelCounts.contains(channelCount)
    }

    private enum CodingKeys: String, CodingKey {
        case encoding
        case sampleRatesHertz
        case channelCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            encoding: container.decode(MeetingTranscriptionAudioEncoding.self, forKey: .encoding),
            sampleRatesHertz: container.decode([Int].self, forKey: .sampleRatesHertz),
            channelCounts: container.decode([Int].self, forKey: .channelCounts)
        )
    }
}

struct MeetingTranscriptionCapabilityCondition: Codable, Hashable {
    let identifier: String
    let value: String?

    init(identifier: String, value: String? = nil) throws {
        self.identifier = try MeetingTranscriptionValidation.normalizedIdentifier(identifier, field: "condition.identifier")
        self.value = try value.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "condition.value", maximumLength: 500)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            identifier: container.decode(String.self, forKey: .identifier),
            value: container.decodeIfPresent(String.self, forKey: .value)
        )
    }
}

enum MeetingTranscriptionCapabilityAvailability: String, Codable, CaseIterable, Hashable {
    case supported
    case unsupported
    case conditional
}

struct MeetingTranscriptionCapabilitySupport: Codable, Hashable {
    let availability: MeetingTranscriptionCapabilityAvailability
    let conditions: [MeetingTranscriptionCapabilityCondition]

    init(
        _ availability: MeetingTranscriptionCapabilityAvailability,
        conditions: [MeetingTranscriptionCapabilityCondition] = []
    ) throws {
        guard conditions.count <= 32, Set(conditions.map(\.identifier)).count == conditions.count else {
            throw MeetingTranscriptionValidationError.invalidCapability("conditions")
        }
        guard availability == .conditional ? !conditions.isEmpty : conditions.isEmpty else {
            throw MeetingTranscriptionValidationError.invalidCapability("availability")
        }
        self.availability = availability
        self.conditions = conditions
    }

    private init(unchecked availability: MeetingTranscriptionCapabilityAvailability) {
        self.availability = availability
        conditions = []
    }

    static var supported: Self {
        Self(unchecked: .supported)
    }

    static var unsupported: Self {
        Self(unchecked: .unsupported)
    }

    private enum CodingKeys: String, CodingKey {
        case availability
        case conditions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            container.decode(MeetingTranscriptionCapabilityAvailability.self, forKey: .availability),
            conditions: container.decode([MeetingTranscriptionCapabilityCondition].self, forKey: .conditions)
        )
    }
}

struct MeetingTranscriptionSessionDurationSupport: Codable, Hashable {
    let support: MeetingTranscriptionCapabilitySupport
    let maximumSeconds: Int?

    init(support: MeetingTranscriptionCapabilitySupport, maximumSeconds: Int?) throws {
        if let maximumSeconds {
            guard support.availability != .unsupported, 1 ... 604_800 ~= maximumSeconds else {
                throw MeetingTranscriptionValidationError.invalidCapability("maximumSessionDuration")
            }
        }
        if support.availability == .supported {
            guard maximumSeconds != nil else {
                throw MeetingTranscriptionValidationError.invalidCapability("maximumSessionDuration")
            }
        }
        self.support = support
        self.maximumSeconds = maximumSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case support
        case maximumSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            support: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .support),
            maximumSeconds: container.decodeIfPresent(Int.self, forKey: .maximumSeconds)
        )
    }
}

struct MeetingTranscriptionCapabilities: Codable, Hashable {
    let modes: Set<MeetingTranscriptionMode>
    let inputFormats: [MeetingTranscriptionInputFormat]
    let timing: MeetingTranscriptionCapabilitySupport
    let confidence: MeetingTranscriptionCapabilitySupport
    let partialResults: MeetingTranscriptionCapabilitySupport
    let diarization: MeetingTranscriptionCapabilitySupport
    let languageIdentification: MeetingTranscriptionCapabilitySupport
    let keyterms: MeetingTranscriptionCapabilitySupport
    let sessionDuration: MeetingTranscriptionSessionDurationSupport

    init(
        modes: Set<MeetingTranscriptionMode>,
        inputFormats: [MeetingTranscriptionInputFormat],
        timing: MeetingTranscriptionCapabilitySupport,
        confidence: MeetingTranscriptionCapabilitySupport,
        partialResults: MeetingTranscriptionCapabilitySupport,
        diarization: MeetingTranscriptionCapabilitySupport,
        languageIdentification: MeetingTranscriptionCapabilitySupport,
        keyterms: MeetingTranscriptionCapabilitySupport,
        sessionDuration: MeetingTranscriptionSessionDurationSupport
    ) throws {
        guard !modes.isEmpty, inputFormats.count <= 32, !inputFormats.isEmpty else {
            throw MeetingTranscriptionValidationError.invalidCapability("modesOrInputFormats")
        }
        guard Set(inputFormats.map(\.encoding)).count == inputFormats.count else {
            throw MeetingTranscriptionValidationError.duplicateValue("inputFormats.encoding")
        }
        self.modes = modes
        self.inputFormats = inputFormats
        self.timing = timing
        self.confidence = confidence
        self.partialResults = partialResults
        self.diarization = diarization
        self.languageIdentification = languageIdentification
        self.keyterms = keyterms
        self.sessionDuration = sessionDuration
    }

    private enum CodingKeys: String, CodingKey {
        case modes
        case inputFormats
        case timing
        case confidence
        case partialResults
        case diarization
        case languageIdentification
        case keyterms
        case sessionDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            modes: container.decode(Set<MeetingTranscriptionMode>.self, forKey: .modes),
            inputFormats: container.decode([MeetingTranscriptionInputFormat].self, forKey: .inputFormats),
            timing: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .timing),
            confidence: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .confidence),
            partialResults: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .partialResults),
            diarization: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .diarization),
            languageIdentification: container.decode(
                MeetingTranscriptionCapabilitySupport.self,
                forKey: .languageIdentification
            ),
            keyterms: container.decode(MeetingTranscriptionCapabilitySupport.self, forKey: .keyterms),
            sessionDuration: container.decode(MeetingTranscriptionSessionDurationSupport.self, forKey: .sessionDuration)
        )
    }
}

enum MeetingTranscriptionProcessingClass: String, Codable, CaseIterable, Hashable {
    case localDevice
    case providerCloud
    case privateDeployment
}

enum MeetingTranscriptionDataRetentionClass: String, Codable, CaseIterable, Hashable {
    case none
    case transient
    case providerDefault
    case configurable
}

struct MeetingTranscriptionPrivacyDescriptor: Codable, Hashable {
    let processing: MeetingTranscriptionProcessingClass
    let supportedRetention: Set<MeetingTranscriptionDataRetentionClass>
    let metadata: [String: String]

    init(
        processing: MeetingTranscriptionProcessingClass,
        supportedRetention: Set<MeetingTranscriptionDataRetentionClass>,
        metadata: [String: String] = [:]
    ) throws {
        guard !supportedRetention.isEmpty, supportedRetention.count <= 8 else {
            throw MeetingTranscriptionValidationError.invalidValue("supportedRetention")
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "privacy.metadata")
        self.processing = processing
        self.supportedRetention = supportedRetention
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case processing
        case supportedRetention
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            processing: container.decode(MeetingTranscriptionProcessingClass.self, forKey: .processing),
            supportedRetention: container.decode(
                Set<MeetingTranscriptionDataRetentionClass>.self,
                forKey: .supportedRetention
            ),
            metadata: container.decode([String: String].self, forKey: .metadata)
        )
    }
}

struct MeetingTranscriptionRegionDescriptor: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let jurisdiction: String?
    let metadata: [String: String]

    init(id: String, displayName: String, jurisdiction: String? = nil, metadata: [String: String] = [:]) throws {
        self.id = try MeetingTranscriptionValidation.normalizedIdentifier(id, field: "region.id")
        self.displayName = try MeetingTranscriptionValidation.normalizedText(
            displayName,
            field: "region.displayName",
            maximumLength: 120
        )
        self.jurisdiction = try jurisdiction.map {
            try MeetingTranscriptionValidation.normalizedText($0, field: "region.jurisdiction", maximumLength: 120)
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "region.metadata")
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case jurisdiction
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            jurisdiction: container.decodeIfPresent(String.self, forKey: .jurisdiction),
            metadata: container.decode([String: String].self, forKey: .metadata)
        )
    }
}

struct MeetingTranscriptionPrice: Codable, Hashable {
    let billingUnit: String
    let unitQuantity: Int
    let priceMicros: Int64

    init(billingUnit: String, unitQuantity: Int, priceMicros: Int64) throws {
        self.billingUnit = try MeetingTranscriptionValidation.normalizedIdentifier(
            billingUnit,
            field: "price.billingUnit"
        )
        guard unitQuantity > 0, unitQuantity <= 1_000_000_000, priceMicros >= 0 else {
            throw MeetingTranscriptionValidationError.invalidValue("price")
        }
        self.unitQuantity = unitQuantity
        self.priceMicros = priceMicros
    }

    private enum CodingKeys: String, CodingKey {
        case billingUnit
        case unitQuantity
        case priceMicros
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            billingUnit: container.decode(String.self, forKey: .billingUnit),
            unitQuantity: container.decode(Int.self, forKey: .unitQuantity),
            priceMicros: container.decode(Int64.self, forKey: .priceMicros)
        )
    }
}

struct MeetingTranscriptionPricingSnapshot: Codable, Hashable {
    let snapshotID: String
    let currencyCode: String
    let effectiveAtMilliseconds: Int64
    let expiresAtMilliseconds: Int64?
    let prices: [MeetingTranscriptionPrice]
    let metadata: [String: String]

    init(
        snapshotID: String,
        currencyCode: String,
        effectiveAtMilliseconds: Int64,
        expiresAtMilliseconds: Int64? = nil,
        prices: [MeetingTranscriptionPrice],
        metadata: [String: String] = [:]
    ) throws {
        self.snapshotID = try MeetingTranscriptionValidation.normalizedIdentifier(snapshotID, field: "pricing.snapshotID")
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3,
              normalizedCurrency.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }),
              effectiveAtMilliseconds >= 0,
              expiresAtMilliseconds.map({ $0 > effectiveAtMilliseconds }) ?? true,
              !prices.isEmpty,
              prices.count <= 64,
              Set(prices.map(\.billingUnit)).count == prices.count
        else {
            throw MeetingTranscriptionValidationError.invalidValue("pricing")
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "pricing.metadata")
        self.currencyCode = normalizedCurrency
        self.effectiveAtMilliseconds = effectiveAtMilliseconds
        self.expiresAtMilliseconds = expiresAtMilliseconds
        self.prices = prices
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID
        case currencyCode
        case effectiveAtMilliseconds
        case expiresAtMilliseconds
        case prices
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            snapshotID: container.decode(String.self, forKey: .snapshotID),
            currencyCode: container.decode(String.self, forKey: .currencyCode),
            effectiveAtMilliseconds: container.decode(Int64.self, forKey: .effectiveAtMilliseconds),
            expiresAtMilliseconds: container.decodeIfPresent(Int64.self, forKey: .expiresAtMilliseconds),
            prices: container.decode([MeetingTranscriptionPrice].self, forKey: .prices),
            metadata: container.decode([String: String].self, forKey: .metadata)
        )
    }
}

struct MeetingTranscriptionModelDescriptor: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let capabilities: MeetingTranscriptionCapabilities
    let supportedLanguageCodes: Set<String>
    let regions: [MeetingTranscriptionRegionDescriptor]
    let privacy: MeetingTranscriptionPrivacyDescriptor
    let pricing: MeetingTranscriptionPricingSnapshot?
    let metadata: [String: String]

    init(
        id: String,
        displayName: String,
        capabilities: MeetingTranscriptionCapabilities,
        supportedLanguageCodes: Set<String>,
        regions: [MeetingTranscriptionRegionDescriptor],
        privacy: MeetingTranscriptionPrivacyDescriptor,
        pricing: MeetingTranscriptionPricingSnapshot? = nil,
        metadata: [String: String] = [:]
    ) throws {
        self.id = try MeetingTranscriptionValidation.normalizedIdentifier(id, field: "model.id")
        self.displayName = try MeetingTranscriptionValidation.normalizedText(
            displayName,
            field: "model.displayName",
            maximumLength: 120
        )
        guard supportedLanguageCodes.count <= 256,
              supportedLanguageCodes.allSatisfy(MeetingTranscriptionValidation.isValidLanguageCode),
              !regions.isEmpty,
              regions.count <= 128,
              Set(regions.map(\.id)).count == regions.count
        else {
            throw MeetingTranscriptionValidationError.invalidValue("model.languagesOrRegions")
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "model.metadata")
        self.capabilities = capabilities
        self.supportedLanguageCodes = supportedLanguageCodes
        self.regions = regions
        self.privacy = privacy
        self.pricing = pricing
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case capabilities
        case supportedLanguageCodes
        case regions
        case privacy
        case pricing
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            capabilities: container.decode(MeetingTranscriptionCapabilities.self, forKey: .capabilities),
            supportedLanguageCodes: container.decode(Set<String>.self, forKey: .supportedLanguageCodes),
            regions: container.decode([MeetingTranscriptionRegionDescriptor].self, forKey: .regions),
            privacy: container.decode(MeetingTranscriptionPrivacyDescriptor.self, forKey: .privacy),
            pricing: container.decodeIfPresent(MeetingTranscriptionPricingSnapshot.self, forKey: .pricing),
            metadata: container.decode([String: String].self, forKey: .metadata)
        )
    }
}

struct MeetingTranscriptionProviderDescriptor: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let models: [MeetingTranscriptionModelDescriptor]
    let metadata: [String: String]

    init(
        id: String,
        displayName: String,
        models: [MeetingTranscriptionModelDescriptor],
        metadata: [String: String] = [:]
    ) throws {
        self.id = try MeetingTranscriptionValidation.normalizedIdentifier(id, field: "provider.id")
        self.displayName = try MeetingTranscriptionValidation.normalizedText(
            displayName,
            field: "provider.displayName",
            maximumLength: 120
        )
        guard models.count <= 512, Set(models.map(\.id)).count == models.count else {
            throw MeetingTranscriptionValidationError.invalidValue("provider.models")
        }
        try MeetingTranscriptionValidation.validateMetadata(metadata, field: "provider.metadata")
        self.models = models
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case models
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            models: container.decode([MeetingTranscriptionModelDescriptor].self, forKey: .models),
            metadata: container.decode([String: String].self, forKey: .metadata)
        )
    }

    func model(id: String) -> MeetingTranscriptionModelDescriptor? {
        models.first { $0.id == id }
    }
}

enum MeetingTranscriptionValidation {
    static func normalizedIdentifier(_ value: String, field: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw MeetingTranscriptionValidationError.emptyValue(field) }
        guard normalized.utf8.count <= 128 else { throw MeetingTranscriptionValidationError.valueTooLong(field) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        guard normalized.unicodeScalars.allSatisfy(allowed.contains) else {
            throw MeetingTranscriptionValidationError.invalidValue(field)
        }
        return normalized
    }

    static func normalizedText(_ value: String, field: String, maximumLength: Int) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw MeetingTranscriptionValidationError.emptyValue(field) }
        guard normalized.count <= maximumLength else { throw MeetingTranscriptionValidationError.valueTooLong(field) }
        guard !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw MeetingTranscriptionValidationError.invalidValue(field)
        }
        return normalized
    }

    static func isValidLanguageCode(_ value: String) -> Bool {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard 1 ... 3 ~= components.count else { return false }
        return components.allSatisfy { component in
            1 ... 8 ~= component.count && component.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0)
            }
        }
    }

    static func validateMetadata(_ metadata: [String: String], field: String) throws {
        guard metadata.count <= 64 else { throw MeetingTranscriptionValidationError.invalidValue(field) }
        for (key, value) in metadata {
            _ = try normalizedIdentifier(key, field: field)
            guard value.utf8.count <= 2000,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" })
            else {
                throw MeetingTranscriptionValidationError.invalidValue(field)
            }
        }
    }
}
