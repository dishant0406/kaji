import Foundation

enum MeetingTranscriptionDynamicDescriptorFactory {
    static func providerDescriptor(
        providerID: String,
        displayName: String,
        models: [MeetingDiscoveredTranscriptionModel],
        endpoint: MeetingTranscriptionEndpointSnapshot,
        selectedMode: MeetingTranscriptionMode? = nil,
        diarizationEnabled: Bool = false
    ) throws -> MeetingTranscriptionProviderDescriptor {
        var descriptors: [MeetingTranscriptionModelDescriptor] = []
        for model in models {
            for mode in model.modes where selectedMode == nil || selectedMode == mode {
                try descriptors.append(modelDescriptor(
                    providerID: providerID,
                    model: model,
                    endpoint: endpoint,
                    mode: mode,
                    diarizationEnabled: diarizationEnabled
                ))
            }
        }
        var seen = Set<String>()
        let unique = descriptors.filter { seen.insert($0.id).inserted }
        return try MeetingTranscriptionProviderDescriptor(
            id: providerID,
            displayName: displayName,
            models: unique,
            metadata: [
                "endpointProfileID": endpoint.profileID.uuidString.lowercased(),
                "endpointFingerprint": endpoint.originFingerprint,
                "dynamicModels": "true",
            ]
        )
    }

    static func modelDescriptor(
        providerID: String,
        model: MeetingDiscoveredTranscriptionModel,
        endpoint: MeetingTranscriptionEndpointSnapshot,
        mode: MeetingTranscriptionMode,
        diarizationEnabled: Bool
    ) throws -> MeetingTranscriptionModelDescriptor {
        guard model.modes.contains(mode), endpoint.providerID == providerID else {
            throw MeetingTranscriptionEndpointProfileError.invalidProvider
        }
        let capabilities = try capabilities(
            providerID: providerID,
            mode: mode,
            diarizationEnabled: diarizationEnabled
        )
        let region = try MeetingTranscriptionRegionDescriptor(
            id: endpoint.regionID,
            displayName: endpoint.displayName,
            jurisdiction: nil,
            metadata: [
                "endpointProfileID": endpoint.profileID.uuidString.lowercased(),
                "endpointFingerprint": endpoint.originFingerprint,
            ]
        )
        let privacy = try privacy(providerID: providerID, endpoint: endpoint)
        var metadata = model.metadata
        metadata["capabilityConfidence"] = model.capabilityConfidence.rawValue
        return try MeetingTranscriptionModelDescriptor(
            id: model.id,
            displayName: model.displayName,
            capabilities: capabilities,
            supportedLanguageCodes: model.languageCodes,
            regions: [region],
            privacy: privacy,
            metadata: metadata
        )
    }

    static func manualModel(
        id: String,
        displayName: String? = nil,
        mode: MeetingTranscriptionMode
    ) throws -> MeetingDiscoveredTranscriptionModel {
        try MeetingDiscoveredTranscriptionModel(
            id: id,
            displayName: displayName ?? id,
            modes: [mode],
            capabilityConfidence: .manual,
            metadata: ["compatibility": "unverified"]
        )
    }

    private static func capabilities(
        providerID: String,
        mode: MeetingTranscriptionMode,
        diarizationEnabled: Bool
    ) throws -> MeetingTranscriptionCapabilities {
        let input = try MeetingTranscriptionInputFormat(
            encoding: .pcmSigned16LittleEndian,
            sampleRatesHertz: providerID == OpenAIMeetingTranscriptionProvider.providerID && mode == .cloudRealtime
                ? [24000] : [16000],
            channelCounts: [1]
        )
        let timing: MeetingTranscriptionCapabilitySupport = .supported
        let confidence: MeetingTranscriptionCapabilitySupport = providerID == DeepgramMeetingTranscriptionProvider.providerID ||
            providerID == ElevenLabsScribeMeetingTranscriptionProvider.providerID ||
            providerID == AssemblyAIMeetingTranscriptionProvider.providerID
            ? .supported : .unsupported
        let partials: MeetingTranscriptionCapabilitySupport = mode == .cloudRealtime ? .supported : .unsupported
        let diarization: MeetingTranscriptionCapabilitySupport = if providerID == OpenAIMeetingTranscriptionProvider.providerID {
            mode == .cloudBatch && diarizationEnabled ? .supported : .unsupported
        } else if providerID == ElevenLabsScribeMeetingTranscriptionProvider.providerID {
            mode == .cloudBatch ? .supported : .unsupported
        } else if providerID == DeepgramMeetingTranscriptionProvider.providerID ||
            providerID == AssemblyAIMeetingTranscriptionProvider.providerID
        {
            .supported
        } else {
            .unsupported
        }
        let keyterms: MeetingTranscriptionCapabilitySupport = providerID == OpenAIMeetingTranscriptionProvider
            .providerID && mode == .cloudRealtime
            ? .unsupported : .supported
        let maximumSeconds = maximumSessionSeconds(providerID: providerID, mode: mode)
        let durationSupport = try sessionDurationSupport(maximumSeconds: maximumSeconds)
        return try MeetingTranscriptionCapabilities(
            modes: [mode],
            inputFormats: [input],
            timing: timing,
            confidence: confidence,
            partialResults: partials,
            diarization: diarization,
            languageIdentification: .supported,
            keyterms: keyterms,
            sessionDuration: MeetingTranscriptionSessionDurationSupport(
                support: durationSupport,
                maximumSeconds: maximumSeconds
            )
        )
    }

    private static func sessionDurationSupport(
        maximumSeconds: Int?
    ) throws -> MeetingTranscriptionCapabilitySupport {
        guard maximumSeconds == nil else { return .supported }
        let condition = try MeetingTranscriptionCapabilityCondition(
            identifier: "provider-session-limit",
            value: "The endpoint controls the maximum session duration."
        )
        return try MeetingTranscriptionCapabilitySupport(.conditional, conditions: [condition])
    }

    private static func privacy(
        providerID: String,
        endpoint: MeetingTranscriptionEndpointSnapshot
    ) throws -> MeetingTranscriptionPrivacyDescriptor {
        let processing: MeetingTranscriptionProcessingClass = endpoint.source == .custom ? .privateDeployment : .providerCloud
        let retention: Set<MeetingTranscriptionDataRetentionClass> = switch providerID {
        case FluidAudioMeetingTranscriptionProvider.providerID:
            [.none]
        default:
            endpoint.source == .custom ? [.configurable] : [.none, .providerDefault]
        }
        return try MeetingTranscriptionPrivacyDescriptor(
            processing: processing,
            supportedRetention: retention,
            metadata: endpoint.source == .custom
                ? ["operatorPolicy": "custom-endpoint-unverified"]
                : ["operatorPolicy": "provider-account-policy"]
        )
    }

    private static func maximumSessionSeconds(providerID: String, mode: MeetingTranscriptionMode) -> Int? {
        guard mode == .cloudRealtime else { return 600 }
        switch providerID {
        case OpenAIMeetingTranscriptionProvider.providerID:
            return 3600
        case AssemblyAIMeetingTranscriptionProvider.providerID:
            return 10800
        case ElevenLabsScribeMeetingTranscriptionProvider.providerID:
            return 14400
        default:
            return nil
        }
    }
}
