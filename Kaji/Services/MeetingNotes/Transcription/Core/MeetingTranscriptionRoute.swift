import Foundation

struct MeetingTranscriptionFallback: Codable, Hashable {
    let providerID: String
    let modelID: String
    let regionID: String
    let mode: MeetingTranscriptionMode

    init(providerID: String, modelID: String, regionID: String, mode: MeetingTranscriptionMode) throws {
        self.providerID = try MeetingTranscriptionValidation.normalizedIdentifier(providerID, field: "fallback.providerID")
        self.modelID = try MeetingTranscriptionValidation.normalizedIdentifier(modelID, field: "fallback.modelID")
        self.regionID = try MeetingTranscriptionValidation.normalizedIdentifier(regionID, field: "fallback.regionID")
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case modelID
        case regionID
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providerID: container.decode(String.self, forKey: .providerID),
            modelID: container.decode(String.self, forKey: .modelID),
            regionID: container.decode(String.self, forKey: .regionID),
            mode: container.decode(MeetingTranscriptionMode.self, forKey: .mode)
        )
    }
}

struct MeetingTranscriptionPrivacyIdentity: Codable, Hashable {
    let providerID: String
    let modelID: String
    let regionID: String
    let mode: MeetingTranscriptionMode
    let retention: MeetingTranscriptionDataRetentionClass
}

struct MeetingTranscriptionRoute: Codable, Hashable {
    let providerID: String
    let modelID: String
    let languageCodes: [String]
    let regionID: String
    let mode: MeetingTranscriptionMode
    let diarizationEnabled: Bool
    let retention: MeetingTranscriptionDataRetentionClass
    let fallbacks: [MeetingTranscriptionFallback]
    let privacyIdentity: MeetingTranscriptionPrivacyIdentity

    init(
        providerID: String,
        modelID: String,
        languageCodes: [String],
        regionID: String,
        mode: MeetingTranscriptionMode,
        diarizationEnabled: Bool,
        retention: MeetingTranscriptionDataRetentionClass,
        fallbacks: [MeetingTranscriptionFallback] = []
    ) throws {
        let providerID = try MeetingTranscriptionValidation.normalizedIdentifier(providerID, field: "route.providerID")
        let modelID = try MeetingTranscriptionValidation.normalizedIdentifier(modelID, field: "route.modelID")
        let regionID = try MeetingTranscriptionValidation.normalizedIdentifier(regionID, field: "route.regionID")
        guard languageCodes.count <= 16,
              Set(languageCodes).count == languageCodes.count,
              languageCodes.allSatisfy(MeetingTranscriptionValidation.isValidLanguageCode),
              fallbacks.count <= 8
        else {
            throw MeetingTranscriptionValidationError.invalidRoute("languagesOrFallbacks")
        }
        let validatedFallbacks = try fallbacks.map {
            try MeetingTranscriptionFallback(
                providerID: $0.providerID,
                modelID: $0.modelID,
                regionID: $0.regionID,
                mode: $0.mode
            )
        }
        let routeKeys = validatedFallbacks.map { "\($0.providerID)|\($0.modelID)|\($0.regionID)|\($0.mode.rawValue)" }
        guard Set(routeKeys).count == routeKeys.count else {
            throw MeetingTranscriptionValidationError.duplicateValue("fallbacks")
        }
        guard !validatedFallbacks.contains(where: {
            $0.providerID == providerID && $0.modelID == modelID && $0.regionID == regionID && $0.mode == mode
        })
        else {
            throw MeetingTranscriptionValidationError.invalidRoute("fallbackMatchesPrimary")
        }
        self.providerID = providerID
        self.modelID = modelID
        self.languageCodes = languageCodes
        self.regionID = regionID
        self.mode = mode
        self.diarizationEnabled = diarizationEnabled
        self.retention = retention
        self.fallbacks = validatedFallbacks
        privacyIdentity = MeetingTranscriptionPrivacyIdentity(
            providerID: providerID,
            modelID: modelID,
            regionID: regionID,
            mode: mode,
            retention: retention
        )
    }

    func validate(against descriptor: MeetingTranscriptionProviderDescriptor) throws {
        guard descriptor.id == providerID, let model = descriptor.model(id: modelID) else {
            throw MeetingTranscriptionValidationError.unsupportedValue("providerOrModel")
        }
        guard model.capabilities.modes.contains(mode), model.regions.contains(where: { $0.id == regionID }) else {
            throw MeetingTranscriptionValidationError.unsupportedValue("modeOrRegion")
        }
        guard model.privacy.supportedRetention.contains(retention) else {
            throw MeetingTranscriptionValidationError.unsupportedValue("retention")
        }
        guard languageCodes.allSatisfy({ model.supportedLanguageCodes.isEmpty || model.supportedLanguageCodes.contains($0) }) else {
            throw MeetingTranscriptionValidationError.unsupportedValue("languageCodes")
        }
        if diarizationEnabled, model.capabilities.diarization.availability == .unsupported {
            throw MeetingTranscriptionValidationError.unsupportedValue("diarization")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case modelID
        case languageCodes
        case regionID
        case mode
        case diarizationEnabled
        case retention
        case fallbacks
        case privacyIdentity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedIdentity = try container.decode(MeetingTranscriptionPrivacyIdentity.self, forKey: .privacyIdentity)
        try self.init(
            providerID: container.decode(String.self, forKey: .providerID),
            modelID: container.decode(String.self, forKey: .modelID),
            languageCodes: container.decode([String].self, forKey: .languageCodes),
            regionID: container.decode(String.self, forKey: .regionID),
            mode: container.decode(MeetingTranscriptionMode.self, forKey: .mode),
            diarizationEnabled: container.decode(Bool.self, forKey: .diarizationEnabled),
            retention: container.decode(MeetingTranscriptionDataRetentionClass.self, forKey: .retention),
            fallbacks: container.decode([MeetingTranscriptionFallback].self, forKey: .fallbacks)
        )
        guard decodedIdentity == privacyIdentity else {
            throw MeetingTranscriptionValidationError.invalidRoute("privacyIdentity")
        }
    }
}
