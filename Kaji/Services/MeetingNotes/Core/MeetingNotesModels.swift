import Foundation

struct MeetingEvidence: Codable, Hashable {
    let transcriptSegmentID: UUID
    let exactQuote: String
}

struct MeetingDecision: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var evidence: [MeetingEvidence]
    var isPinned: Bool
}

struct MeetingActionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var owner: String?
    var dueAtMilliseconds: Int64?
    var isCompleted: Bool
    var evidence: [MeetingEvidence]
    var isPinned: Bool
}

struct MeetingOpenQuestion: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isResolved: Bool
    var evidence: [MeetingEvidence]
    var isPinned: Bool
}

enum MeetingRiskSeverity: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case critical
}

struct MeetingRisk: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var mitigation: String?
    var severity: MeetingRiskSeverity
    var evidence: [MeetingEvidence]
    var isPinned: Bool
}

struct MeetingNotesSnapshot: Codable, Equatable {
    let sessionID: UUID
    var revision: Int
    var title: String
    var summary: String
    var linkedProjectIDs: [UUID]
    var decisions: [MeetingDecision]
    var actionItems: [MeetingActionItem]
    var openQuestions: [MeetingOpenQuestion]
    var risks: [MeetingRisk]
    var updatedAtMilliseconds: Int64

    static func empty(sessionID: UUID, title: String, createdAtMilliseconds: Int64) -> Self {
        Self(
            sessionID: sessionID,
            revision: 0,
            title: title,
            summary: "",
            linkedProjectIDs: [],
            decisions: [],
            actionItems: [],
            openQuestions: [],
            risks: [],
            updatedAtMilliseconds: createdAtMilliseconds
        )
    }
}

enum MeetingNotesRevisionSource: String, Codable, CaseIterable {
    case synthesis
    case userEdit
}

struct MeetingNotesRevision: Identifiable, Codable, Equatable {
    let id: UUID
    let patchID: UUID
    let baseRevision: Int
    let resultingRevision: Int
    let createdAtMilliseconds: Int64
    let source: MeetingNotesRevisionSource
}

struct MeetingRecordingGap: Identifiable, Codable, Equatable {
    let id: UUID
    let trackID: UUID
    let firstSequenceNumber: Int64
    let lastSequenceNumber: Int64
    let droppedBufferCount: Int
    let droppedFrameCount: Int64
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let reason: String
}

struct MeetingTranscriptionGap: Identifiable, Codable, Equatable {
    let id: UUID
    let trackID: UUID
    let sampleRange: MeetingSampleRange
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let classification: MeetingTranscriptionFailureClassification
    let code: String
}

struct MeetingTranscriptionTrackHealthRecord: Identifiable, Codable, Equatable {
    let trackID: UUID
    var providerEpoch: MeetingProviderEpoch
    var state: MeetingTranscriptionTrackRuntimeState
    var updatedAtMilliseconds: Int64
    var code: String?

    var id: UUID { trackID }
}

struct MeetingCommittedTranscriptMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    let operationID: UUID?
    let trackID: UUID
    let source: MeetingTranscriptionSource
    let providerID: String
    let modelID: String
    let regionID: String
    let mode: MeetingTranscriptionMode
    let providerEpoch: MeetingProviderEpoch
    let confidence: Double?
    let words: [MeetingNormalizedWord]
    var speaker: MeetingNormalizedSpeaker?
    let language: MeetingNormalizedLanguage?
    let committedAtMilliseconds: Int64
}

struct MeetingSessionConfiguration: Codable, Equatable {
    static let currentVersion = 4
    static let currentDisclosureVersion = 4
    static let consentValidityMilliseconds: Int64 = 5 * 60 * 1000

    let version: Int
    let synthesisIntervalMinutes: Int
    let includeSystemAudio: Bool
    let includeMicrophone: Bool
    let retainRawAudio: Bool
    let retentionDays: Int
    let shareProjectContext: Bool
    let contextScope: MeetingProjectContextScope
    let notesProviderID: String
    let notesModelID: String
    let styleInstructions: String
    let transcriptionRoute: MeetingTranscriptionRoute
    let transcriptionEndpoint: MeetingTranscriptionEndpointSnapshot?
    let transcriptionModel: MeetingDiscoveredTranscriptionModel?
    let sttCredentialProfileID: UUID?
    let sttKeyterms: [String]
    let sttMaximumSpeakers: Int?
    let sttProviderOptions: MeetingTranscriptionProviderOptions
    let sttAccountAttestations: [MeetingTranscriptionAccountAttestation]
    let localFallbackEnabled: Bool
    let rawAudioRecipient: String
    let rawAudioRegionID: String
    let rawAudioRetention: MeetingTranscriptionDataRetentionClass
    let disclosureClaims: [String]
    let disclosureVersion: Int
    let consentedAtMilliseconds: Int64
    let consentExpiresAtMilliseconds: Int64

    init(
        version: Int,
        synthesisIntervalMinutes: Int,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        retainRawAudio: Bool,
        retentionDays: Int,
        shareProjectContext: Bool,
        contextScope: MeetingProjectContextScope,
        notesProviderID: String,
        notesModelID: String,
        styleInstructions: String,
        transcriptionRoute: MeetingTranscriptionRoute,
        transcriptionEndpoint: MeetingTranscriptionEndpointSnapshot? = nil,
        transcriptionModel: MeetingDiscoveredTranscriptionModel? = nil,
        sttCredentialProfileID: UUID?,
        sttKeyterms: [String],
        sttMaximumSpeakers: Int?,
        sttProviderOptions: MeetingTranscriptionProviderOptions,
        sttAccountAttestations: [MeetingTranscriptionAccountAttestation],
        localFallbackEnabled: Bool,
        rawAudioRecipient: String,
        rawAudioRegionID: String,
        rawAudioRetention: MeetingTranscriptionDataRetentionClass,
        disclosureClaims: [String],
        disclosureVersion: Int,
        consentedAtMilliseconds: Int64,
        consentExpiresAtMilliseconds: Int64
    ) {
        self.version = version
        self.synthesisIntervalMinutes = synthesisIntervalMinutes
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
        self.retainRawAudio = retainRawAudio
        self.retentionDays = retentionDays
        self.shareProjectContext = shareProjectContext
        self.contextScope = contextScope
        self.notesProviderID = notesProviderID
        self.notesModelID = notesModelID
        self.styleInstructions = styleInstructions
        self.transcriptionRoute = transcriptionRoute
        self.transcriptionEndpoint = transcriptionEndpoint
        self.transcriptionModel = transcriptionModel
        self.sttCredentialProfileID = sttCredentialProfileID
        self.sttKeyterms = sttKeyterms
        self.sttMaximumSpeakers = sttMaximumSpeakers
        self.sttProviderOptions = sttProviderOptions
        self.sttAccountAttestations = sttAccountAttestations
        self.localFallbackEnabled = localFallbackEnabled
        self.rawAudioRecipient = rawAudioRecipient
        self.rawAudioRegionID = rawAudioRegionID
        self.rawAudioRetention = rawAudioRetention
        self.disclosureClaims = disclosureClaims
        self.disclosureVersion = disclosureVersion
        self.consentedAtMilliseconds = consentedAtMilliseconds
        self.consentExpiresAtMilliseconds = consentExpiresAtMilliseconds
    }

    static let legacy = Self(
        version: currentVersion,
        synthesisIntervalMinutes: 5,
        includeSystemAudio: false,
        includeMicrophone: false,
        retainRawAudio: false,
        retentionDays: 30,
        shareProjectContext: false,
        contextScope: .active,
        notesProviderID: "",
        notesModelID: "",
        styleInstructions: "",
        transcriptionRoute: localLegacyRoute(),
        transcriptionEndpoint: nil,
        transcriptionModel: nil,
        sttCredentialProfileID: nil,
        sttKeyterms: [],
        sttMaximumSpeakers: nil,
        sttProviderOptions: .defaults,
        sttAccountAttestations: [],
        localFallbackEnabled: false,
        rawAudioRecipient: "this-mac",
        rawAudioRegionID: FluidAudioMeetingTranscriptionProvider.localRegionID,
        rawAudioRetention: .none,
        disclosureClaims: [],
        disclosureVersion: 0,
        consentedAtMilliseconds: 0,
        consentExpiresAtMilliseconds: 0
    )

    var isModelConfigured: Bool {
        !notesProviderID.isEmpty && !notesModelID.isEmpty
    }

    var persistenceSettings: MeetingNotesSettings {
        (try? MeetingNotesSettings(
            synthesisIntervalMinutes: synthesisIntervalMinutes,
            retainRawAudio: retainRawAudio,
            retentionDays: retentionDays,
            includeSystemAudio: includeSystemAudio,
            shareProjectContext: shareProjectContext
        )) ?? .privacyDefaults
    }

    var sendsRawAudioOffDevice: Bool {
        transcriptionRoute.mode != .localChunked
    }

    var hasCurrentDisclosure: Bool {
        version == Self.currentVersion && disclosureVersion == Self.currentDisclosureVersion
    }

    private static func localLegacyRoute() -> MeetingTranscriptionRoute {
        guard let route = try? MeetingTranscriptionRoute(
            providerID: FluidAudioMeetingTranscriptionProvider.providerID,
            modelID: SpeechInputModel.defaultID,
            languageCodes: [],
            regionID: FluidAudioMeetingTranscriptionProvider.localRegionID,
            mode: .localChunked,
            diarizationEnabled: false,
            retention: .none
        )
        else {
            preconditionFailure("Invalid built-in local transcription route")
        }
        return route
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case synthesisIntervalMinutes
        case includeSystemAudio
        case includeMicrophone
        case retainRawAudio
        case retentionDays
        case shareProjectContext
        case contextScope
        case notesProviderID
        case notesModelID
        case providerID
        case modelID
        case styleInstructions
        case transcriptionRoute
        case sttCredentialProfileID
        case transcriptionEndpoint
        case transcriptionModel
        case sttKeyterms
        case sttMaximumSpeakers
        case sttProviderOptions
        case sttAccountAttestations
        case localFallbackEnabled
        case rawAudioRecipient
        case rawAudioRegionID
        case rawAudioRetention
        case disclosureClaims
        case disclosureVersion
        case consentedAtMilliseconds
        case consentExpiresAtMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.currentVersion
        synthesisIntervalMinutes = try container.decode(Int.self, forKey: .synthesisIntervalMinutes)
        includeSystemAudio = try container.decode(Bool.self, forKey: .includeSystemAudio)
        includeMicrophone = try container.decode(Bool.self, forKey: .includeMicrophone)
        retainRawAudio = try container.decode(Bool.self, forKey: .retainRawAudio)
        retentionDays = try container.decode(Int.self, forKey: .retentionDays)
        shareProjectContext = try container.decode(Bool.self, forKey: .shareProjectContext)
        contextScope = try container.decode(MeetingProjectContextScope.self, forKey: .contextScope)
        notesProviderID = try container.decodeIfPresent(String.self, forKey: .notesProviderID)
            ?? container.decodeIfPresent(String.self, forKey: .providerID)
            ?? ""
        notesModelID = try container.decodeIfPresent(String.self, forKey: .notesModelID)
            ?? container.decodeIfPresent(String.self, forKey: .modelID)
            ?? ""
        styleInstructions = try container.decode(String.self, forKey: .styleInstructions)
        transcriptionRoute = try container.decodeIfPresent(MeetingTranscriptionRoute.self, forKey: .transcriptionRoute)
            ?? Self.legacy.transcriptionRoute
        transcriptionEndpoint = try container.decodeIfPresent(MeetingTranscriptionEndpointSnapshot.self, forKey: .transcriptionEndpoint)
        transcriptionModel = try container.decodeIfPresent(MeetingDiscoveredTranscriptionModel.self, forKey: .transcriptionModel)
        sttCredentialProfileID = try container.decodeIfPresent(UUID.self, forKey: .sttCredentialProfileID)
        sttKeyterms = try container.decodeIfPresent([String].self, forKey: .sttKeyterms) ?? []
        sttMaximumSpeakers = try container.decodeIfPresent(Int.self, forKey: .sttMaximumSpeakers)
        sttProviderOptions = try container.decodeIfPresent(
            MeetingTranscriptionProviderOptions.self,
            forKey: .sttProviderOptions
        ) ?? .defaults
        sttAccountAttestations = try container.decodeIfPresent(
            [MeetingTranscriptionAccountAttestation].self,
            forKey: .sttAccountAttestations
        ) ?? []
        localFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .localFallbackEnabled) ?? false
        rawAudioRecipient = try container.decodeIfPresent(String.self, forKey: .rawAudioRecipient)
            ?? (transcriptionRoute.mode == .localChunked ? "this-mac" : transcriptionRoute.providerID)
        rawAudioRegionID = try container.decodeIfPresent(String.self, forKey: .rawAudioRegionID)
            ?? transcriptionRoute.regionID
        rawAudioRetention = try container.decodeIfPresent(
            MeetingTranscriptionDataRetentionClass.self,
            forKey: .rawAudioRetention
        ) ?? transcriptionRoute.retention
        disclosureClaims = try container.decodeIfPresent([String].self, forKey: .disclosureClaims) ?? []
        disclosureVersion = try container.decodeIfPresent(Int.self, forKey: .disclosureVersion) ?? 0
        consentedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .consentedAtMilliseconds) ?? 0
        consentExpiresAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .consentExpiresAtMilliseconds)
            ?? consentedAtMilliseconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(synthesisIntervalMinutes, forKey: .synthesisIntervalMinutes)
        try container.encode(includeSystemAudio, forKey: .includeSystemAudio)
        try container.encode(includeMicrophone, forKey: .includeMicrophone)
        try container.encode(retainRawAudio, forKey: .retainRawAudio)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(shareProjectContext, forKey: .shareProjectContext)
        try container.encode(contextScope, forKey: .contextScope)
        try container.encode(notesProviderID, forKey: .notesProviderID)
        try container.encode(notesModelID, forKey: .notesModelID)
        try container.encode(styleInstructions, forKey: .styleInstructions)
        try container.encode(transcriptionRoute, forKey: .transcriptionRoute)
        try container.encodeIfPresent(transcriptionEndpoint, forKey: .transcriptionEndpoint)
        try container.encodeIfPresent(transcriptionModel, forKey: .transcriptionModel)
        try container.encodeIfPresent(sttCredentialProfileID, forKey: .sttCredentialProfileID)
        try container.encode(sttKeyterms, forKey: .sttKeyterms)
        try container.encodeIfPresent(sttMaximumSpeakers, forKey: .sttMaximumSpeakers)
        try container.encode(sttProviderOptions, forKey: .sttProviderOptions)
        try container.encode(sttAccountAttestations, forKey: .sttAccountAttestations)
        try container.encode(localFallbackEnabled, forKey: .localFallbackEnabled)
        try container.encode(rawAudioRecipient, forKey: .rawAudioRecipient)
        try container.encode(rawAudioRegionID, forKey: .rawAudioRegionID)
        try container.encode(rawAudioRetention, forKey: .rawAudioRetention)
        try container.encode(disclosureClaims, forKey: .disclosureClaims)
        try container.encode(disclosureVersion, forKey: .disclosureVersion)
        try container.encode(consentedAtMilliseconds, forKey: .consentedAtMilliseconds)
        try container.encode(consentExpiresAtMilliseconds, forKey: .consentExpiresAtMilliseconds)
    }
}

enum MeetingSynthesisStatus: String, Codable, Equatable {
    case idle
    case scheduled
    case generating
    case retryScheduled = "retry_scheduled"
    case failed
    case completed
}

enum MeetingSynthesisErrorCode: String, Codable, Equatable {
    case invalidRequest = "invalid_request"
    case modelUnavailable = "model_unavailable"
    case credentialUnavailable = "credential_unavailable"
    case providerTimeout = "provider_timeout"
    case providerFailure = "provider_failure"
    case invalidResponse = "invalid_response"
    case cancelled

    var allowsAutomaticRetry: Bool {
        switch self {
        case .providerTimeout,
             .providerFailure,
             .invalidResponse,
             .cancelled:
            true
        case .invalidRequest,
             .modelUnavailable,
             .credentialUnavailable:
            false
        }
    }
}

struct MeetingSynthesisState: Codable, Equatable {
    var synthesizedSegmentIDs: Set<UUID>
    var pendingSegmentIDs: Set<UUID>
    var status: MeetingSynthesisStatus
    var attemptCount: Int
    var lastAttemptAtMilliseconds: Int64?
    var nextAttemptAtMilliseconds: Int64?
    var lastErrorCode: MeetingSynthesisErrorCode?

    var isPending: Bool { !pendingSegmentIDs.isEmpty }

    static let empty = Self(
        synthesizedSegmentIDs: [],
        pendingSegmentIDs: [],
        status: .idle,
        attemptCount: 0,
        lastAttemptAtMilliseconds: nil,
        nextAttemptAtMilliseconds: nil,
        lastErrorCode: nil
    )

    private enum CodingKeys: String, CodingKey {
        case synthesizedSegmentIDs
        case pendingSegmentIDs
        case isPending
        case status
        case attemptCount
        case lastAttemptAtMilliseconds
        case nextAttemptAtMilliseconds
        case lastErrorCode
    }

    init(
        synthesizedSegmentIDs: Set<UUID>,
        pendingSegmentIDs: Set<UUID>,
        status: MeetingSynthesisStatus,
        attemptCount: Int,
        lastAttemptAtMilliseconds: Int64?,
        nextAttemptAtMilliseconds: Int64?,
        lastErrorCode: MeetingSynthesisErrorCode?
    ) {
        self.synthesizedSegmentIDs = synthesizedSegmentIDs
        self.pendingSegmentIDs = pendingSegmentIDs
        self.status = status
        self.attemptCount = attemptCount
        self.lastAttemptAtMilliseconds = lastAttemptAtMilliseconds
        self.nextAttemptAtMilliseconds = nextAttemptAtMilliseconds
        self.lastErrorCode = lastErrorCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        synthesizedSegmentIDs = try container.decode(Set<UUID>.self, forKey: .synthesizedSegmentIDs)
        pendingSegmentIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .pendingSegmentIDs) ?? []
        let legacyIsPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        status = try container.decodeIfPresent(MeetingSynthesisStatus.self, forKey: .status)
            ?? (legacyIsPending || !pendingSegmentIDs.isEmpty ? .retryScheduled : .idle)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastAttemptAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .lastAttemptAtMilliseconds)
        nextAttemptAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .nextAttemptAtMilliseconds)
        lastErrorCode = try container.decodeIfPresent(MeetingSynthesisErrorCode.self, forKey: .lastErrorCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(synthesizedSegmentIDs, forKey: .synthesizedSegmentIDs)
        try container.encode(pendingSegmentIDs, forKey: .pendingSegmentIDs)
        try container.encode(isPending, forKey: .isPending)
        try container.encode(status, forKey: .status)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encodeIfPresent(lastAttemptAtMilliseconds, forKey: .lastAttemptAtMilliseconds)
        try container.encodeIfPresent(nextAttemptAtMilliseconds, forKey: .nextAttemptAtMilliseconds)
        try container.encodeIfPresent(lastErrorCode, forKey: .lastErrorCode)
    }
}

struct MeetingSessionDocument: Codable, Equatable {
    static let currentVersion = 3

    let version: Int
    var session: MeetingSession
    var tracks: [MeetingSourceTrack]
    var audioChunks: [MeetingAudioChunkMetadata]
    var transcriptSegments: [MeetingTranscriptSegment]
    var committedTranscriptMetadata: [MeetingCommittedTranscriptMetadata]
    var recordingGaps: [MeetingRecordingGap]
    var transcriptionGaps: [MeetingTranscriptionGap]
    var transcriptionTrackHealth: [MeetingTranscriptionTrackHealthRecord]
    var notes: MeetingNotesSnapshot
    var noteRevisions: [MeetingNotesRevision]
    var configuration: MeetingSessionConfiguration
    var synthesisState: MeetingSynthesisState

    init(
        session: MeetingSession,
        tracks: [MeetingSourceTrack] = [],
        audioChunks: [MeetingAudioChunkMetadata] = [],
        transcriptSegments: [MeetingTranscriptSegment] = [],
        committedTranscriptMetadata: [MeetingCommittedTranscriptMetadata] = [],
        recordingGaps: [MeetingRecordingGap] = [],
        transcriptionGaps: [MeetingTranscriptionGap] = [],
        transcriptionTrackHealth: [MeetingTranscriptionTrackHealthRecord] = [],
        notes: MeetingNotesSnapshot? = nil,
        noteRevisions: [MeetingNotesRevision] = [],
        configuration: MeetingSessionConfiguration = .legacy,
        synthesisState: MeetingSynthesisState = .empty
    ) {
        version = Self.currentVersion
        self.session = session
        self.tracks = tracks
        self.audioChunks = audioChunks
        self.transcriptSegments = transcriptSegments
        self.committedTranscriptMetadata = committedTranscriptMetadata
        self.recordingGaps = recordingGaps
        self.transcriptionGaps = transcriptionGaps
        self.transcriptionTrackHealth = transcriptionTrackHealth
        self.notes = notes ?? .empty(
            sessionID: session.id,
            title: session.title,
            createdAtMilliseconds: session.lifecycle.createdAtMilliseconds
        )
        self.noteRevisions = noteRevisions
        self.configuration = configuration
        self.synthesisState = synthesisState
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case session
        case tracks
        case audioChunks
        case transcriptSegments
        case committedTranscriptMetadata
        case recordingGaps
        case transcriptionGaps
        case transcriptionTrackHealth
        case notes
        case noteRevisions
        case configuration
        case synthesisState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard (1 ... Self.currentVersion).contains(decodedVersion) else {
            throw MeetingDomainError.invalidDocument
        }
        version = Self.currentVersion
        session = try container.decode(MeetingSession.self, forKey: .session)
        tracks = try container.decode([MeetingSourceTrack].self, forKey: .tracks)
        audioChunks = try container.decode([MeetingAudioChunkMetadata].self, forKey: .audioChunks)
        transcriptSegments = try container.decode([MeetingTranscriptSegment].self, forKey: .transcriptSegments)
        committedTranscriptMetadata = try container.decodeIfPresent(
            [MeetingCommittedTranscriptMetadata].self,
            forKey: .committedTranscriptMetadata
        ) ?? []
        recordingGaps = try container.decodeIfPresent([MeetingRecordingGap].self, forKey: .recordingGaps) ?? []
        transcriptionGaps = try container.decodeIfPresent([MeetingTranscriptionGap].self, forKey: .transcriptionGaps) ?? []
        transcriptionTrackHealth = try container.decodeIfPresent(
            [MeetingTranscriptionTrackHealthRecord].self,
            forKey: .transcriptionTrackHealth
        ) ?? []
        notes = try container.decode(MeetingNotesSnapshot.self, forKey: .notes)
        noteRevisions = try container.decode([MeetingNotesRevision].self, forKey: .noteRevisions)
        configuration = try container.decodeIfPresent(MeetingSessionConfiguration.self, forKey: .configuration) ?? .legacy
        synthesisState = try container.decodeIfPresent(MeetingSynthesisState.self, forKey: .synthesisState)
            ?? MeetingSynthesisState(
                synthesizedSegmentIDs: [],
                pendingSegmentIDs: Set(transcriptSegments.filter(\.isFinal).map(\.id)),
                status: transcriptSegments.contains { $0.isFinal } ? .retryScheduled : .idle,
                attemptCount: 0,
                lastAttemptAtMilliseconds: nil,
                nextAttemptAtMilliseconds: nil,
                lastErrorCode: nil
            )
        if synthesisState.pendingSegmentIDs.isEmpty,
           synthesisState.status == .retryScheduled
        {
            synthesisState.pendingSegmentIDs = Set(transcriptSegments.filter {
                $0.isFinal && !synthesisState.synthesizedSegmentIDs.contains($0.id)
            }.map(\.id))
        }
        if synthesisState.status == .generating {
            synthesisState.status = synthesisState.isPending ? .retryScheduled : .completed
            synthesisState.nextAttemptAtMilliseconds = nil
        }
    }
}

enum MeetingNotesPatchOperation: Codable, Equatable {
    case setTitle(String)
    case setSummary(String)
    case setLinkedProjects([UUID])
    case upsertDecision(MeetingDecision)
    case removeDecision(UUID)
    case upsertActionItem(MeetingActionItem)
    case removeActionItem(UUID)
    case upsertOpenQuestion(MeetingOpenQuestion)
    case removeOpenQuestion(UUID)
    case upsertRisk(MeetingRisk)
    case removeRisk(UUID)
}

struct MeetingNotesPatch: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let baseRevision: Int
    let operations: [MeetingNotesPatchOperation]

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        baseRevision: Int,
        operations: [MeetingNotesPatchOperation]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.baseRevision = baseRevision
        self.operations = operations
    }
}
