import Foundation

enum MeetingTranscriptionAccountAttestationKind: String, Codable, CaseIterable, Hashable {
    case openAIZeroDataRetention
    case assemblyAITrainingOptOut
    case elevenLabsZeroRetentionMode

    var providerID: String {
        switch self {
        case .openAIZeroDataRetention:
            OpenAIMeetingTranscriptionProvider.providerID
        case .assemblyAITrainingOptOut:
            AssemblyAIMeetingTranscriptionProvider.providerID
        case .elevenLabsZeroRetentionMode:
            ElevenLabsScribeMeetingTranscriptionProvider.providerID
        }
    }

    var claim: String {
        switch self {
        case .openAIZeroDataRetention:
            "I attest that this OpenAI organization is approved for Zero Data Retention. "
                + "Kaji cannot independently verify this account setting."
        case .assemblyAITrainingOptOut:
            "I attest that training opt-out is enabled for this AssemblyAI account. Kaji cannot independently verify this account setting."
        case .elevenLabsZeroRetentionMode:
            "I attest that Enterprise Zero Retention Mode is enabled for this ElevenLabs workspace. "
                + "Kaji cannot independently verify this account setting."
        }
    }
}

struct MeetingTranscriptionAccountAttestation: Codable, Equatable, Hashable, Identifiable {
    let kind: MeetingTranscriptionAccountAttestationKind
    let providerID: String
    let claim: String
    let acceptedAtMilliseconds: Int64

    var id: MeetingTranscriptionAccountAttestationKind { kind }

    init(kind: MeetingTranscriptionAccountAttestationKind, acceptedAtMilliseconds: Int64) throws {
        guard acceptedAtMilliseconds >= 0 else { throw CocoaError(.validationMissingMandatoryProperty) }
        self.kind = kind
        providerID = kind.providerID
        claim = kind.claim
        self.acceptedAtMilliseconds = acceptedAtMilliseconds
    }

    var isExact: Bool {
        providerID == kind.providerID && claim == kind.claim && acceptedAtMilliseconds >= 0
    }
}

struct MeetingTranscriptionProviderOptions: Codable, Equatable {
    var automaticLanguageDetection: Bool
    var noVerbatim: Bool
    var tagAudioEvents: Bool
    var trainingOptOutEnabled: Bool
    var transcriptTTLHours: Int?

    static let defaults = Self(
        automaticLanguageDetection: true,
        noVerbatim: false,
        tagAudioEvents: true,
        trainingOptOutEnabled: false,
        transcriptTTLHours: nil
    )

    mutating func normalize() {
        if let transcriptTTLHours {
            self.transcriptTTLHours = min(8760, max(1, transcriptTTLHours))
        }
    }
}

struct MeetingNotesIntegrationSettings: Codable, Equatable {
    static let currentVersion = 4

    var version: Int
    var synthesisIntervalMinutes: Int
    var includeSystemAudio: Bool
    var includeMicrophone: Bool
    var retentionDays: Int
    var shareProjectContext: Bool
    var contextScope: MeetingProjectContextScope
    var notesProviderID: String
    var notesModelID: String
    var styleInstructions: String
    var sttProviderID: String
    var sttModelID: String
    var sttMode: MeetingTranscriptionMode
    var sttRegionID: String
    var sttCredentialProfileID: UUID?
    var sttEndpointProfileID: UUID?
    var sttEndpointSnapshot: MeetingTranscriptionEndpointSnapshot?
    var sttModelMetadata: MeetingDiscoveredTranscriptionModel?
    var sttLanguageCodes: [String]
    var sttDiarizationEnabled: Bool
    var sttRetention: MeetingTranscriptionDataRetentionClass
    var sttKeyterms: [String]
    var sttMaximumSpeakers: Int?
    var sttProviderOptions: MeetingTranscriptionProviderOptions
    var sttAccountAttestations: [MeetingTranscriptionAccountAttestation]
    var localFallbackEnabled: Bool

    init(
        version: Int,
        synthesisIntervalMinutes: Int,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        retentionDays: Int,
        shareProjectContext: Bool,
        contextScope: MeetingProjectContextScope,
        notesProviderID: String,
        notesModelID: String,
        styleInstructions: String,
        sttProviderID: String,
        sttModelID: String,
        sttMode: MeetingTranscriptionMode,
        sttRegionID: String,
        sttCredentialProfileID: UUID?,
        sttEndpointProfileID: UUID? = nil,
        sttEndpointSnapshot: MeetingTranscriptionEndpointSnapshot? = nil,
        sttModelMetadata: MeetingDiscoveredTranscriptionModel? = nil,
        sttLanguageCodes: [String],
        sttDiarizationEnabled: Bool,
        sttRetention: MeetingTranscriptionDataRetentionClass,
        sttKeyterms: [String],
        sttMaximumSpeakers: Int?,
        sttProviderOptions: MeetingTranscriptionProviderOptions,
        sttAccountAttestations: [MeetingTranscriptionAccountAttestation],
        localFallbackEnabled: Bool
    ) {
        self.version = version
        self.synthesisIntervalMinutes = synthesisIntervalMinutes
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
        self.retentionDays = retentionDays
        self.shareProjectContext = shareProjectContext
        self.contextScope = contextScope
        self.notesProviderID = notesProviderID
        self.notesModelID = notesModelID
        self.styleInstructions = styleInstructions
        self.sttProviderID = sttProviderID
        self.sttModelID = sttModelID
        self.sttMode = sttMode
        self.sttRegionID = sttRegionID
        self.sttCredentialProfileID = sttCredentialProfileID
        self.sttEndpointProfileID = sttEndpointProfileID
        self.sttEndpointSnapshot = sttEndpointSnapshot
        self.sttModelMetadata = sttModelMetadata
        self.sttLanguageCodes = sttLanguageCodes
        self.sttDiarizationEnabled = sttDiarizationEnabled
        self.sttRetention = sttRetention
        self.sttKeyterms = sttKeyterms
        self.sttMaximumSpeakers = sttMaximumSpeakers
        self.sttProviderOptions = sttProviderOptions
        self.sttAccountAttestations = sttAccountAttestations
        self.localFallbackEnabled = localFallbackEnabled
    }

    static let defaults = Self(
        version: currentVersion,
        synthesisIntervalMinutes: 2,
        includeSystemAudio: true,
        includeMicrophone: true,
        retentionDays: 30,
        shareProjectContext: false,
        contextScope: .active,
        notesProviderID: "",
        notesModelID: "",
        styleInstructions: "",
        sttProviderID: FluidAudioMeetingTranscriptionProvider.providerID,
        sttModelID: "",
        sttMode: .localChunked,
        sttRegionID: FluidAudioMeetingTranscriptionProvider.localRegionID,
        sttCredentialProfileID: nil,
        sttEndpointProfileID: nil,
        sttEndpointSnapshot: nil,
        sttModelMetadata: nil,
        sttLanguageCodes: [],
        sttDiarizationEnabled: false,
        sttRetention: .none,
        sttKeyterms: [],
        sttMaximumSpeakers: nil,
        sttProviderOptions: .defaults,
        sttAccountAttestations: [],
        localFallbackEnabled: false
    )

    var modelSelector: String {
        guard isModelConfigured else { return "" }
        return "\(notesProviderID)/\(notesModelID)"
    }

    var isModelConfigured: Bool {
        !notesProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !notesModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var persistenceSettings: MeetingNotesSettings {
        (try? MeetingNotesSettings(
            synthesisIntervalMinutes: synthesisIntervalMinutes,
            retainRawAudio: false,
            retentionDays: retentionDays,
            includeSystemAudio: includeSystemAudio,
            shareProjectContext: shareProjectContext
        )) ?? .privacyDefaults
    }

    func sessionConfiguration(
        consentedAtMilliseconds: Int64,
        consentValidityMilliseconds: Int64 = MeetingSessionConfiguration.consentValidityMilliseconds
    ) -> MeetingSessionConfiguration {
        MeetingSessionConfiguration(
            version: MeetingSessionConfiguration.currentVersion,
            synthesisIntervalMinutes: synthesisIntervalMinutes,
            includeSystemAudio: includeSystemAudio,
            includeMicrophone: includeMicrophone,
            retainRawAudio: false,
            retentionDays: retentionDays,
            shareProjectContext: shareProjectContext,
            contextScope: contextScope,
            notesProviderID: notesProviderID,
            notesModelID: notesModelID,
            styleInstructions: styleInstructions,
            transcriptionRoute: transcriptionRoute,
            transcriptionEndpoint: sttEndpointSnapshot,
            transcriptionModel: sttModelMetadata,
            sttCredentialProfileID: sttCredentialProfileID,
            sttKeyterms: sttKeyterms,
            sttMaximumSpeakers: sttMaximumSpeakers,
            sttProviderOptions: sttProviderOptions,
            sttAccountAttestations: sttAccountAttestations,
            localFallbackEnabled: localFallbackEnabled,
            rawAudioRecipient: rawAudioRecipient,
            rawAudioRegionID: sttEndpointSnapshot?.regionID ?? sttRegionID,
            rawAudioRetention: sttRetention,
            disclosureClaims: disclosureClaims,
            disclosureVersion: MeetingSessionConfiguration.currentDisclosureVersion,
            consentedAtMilliseconds: consentedAtMilliseconds,
            consentExpiresAtMilliseconds: consentedAtMilliseconds + consentValidityMilliseconds
        )
    }

    private var rawAudioRecipient: String {
        guard sttMode != .localChunked else { return "this-mac" }
        guard let snapshot = sttEndpointSnapshot else { return sttProviderID }
        return [snapshot.restBaseURL, snapshot.webSocketBaseURL]
            .compactMap { $0.flatMap { URL(string: $0)?.host } }
            .first ?? snapshot.displayName
    }

    var transcriptionRoute: MeetingTranscriptionRoute {
        let fallbacks: [MeetingTranscriptionFallback] = if localFallbackEnabled, sttMode != .localChunked,
                                                           let fallback = try? MeetingTranscriptionFallback(
                                                               providerID: FluidAudioMeetingTranscriptionProvider.providerID,
                                                               modelID: SpeechInputModel.defaultID,
                                                               regionID: FluidAudioMeetingTranscriptionProvider.localRegionID,
                                                               mode: .localChunked
                                                           )
        {
            [fallback]
        } else {
            []
        }
        return (try? MeetingTranscriptionRoute(
            providerID: sttProviderID,
            modelID: sttModelID,
            languageCodes: sttLanguageCodes,
            regionID: sttRegionID,
            mode: sttMode,
            diarizationEnabled: sttDiarizationEnabled,
            retention: sttRetention,
            fallbacks: fallbacks
        )) ?? Self.defaults.transcriptionRoute
    }

    mutating func normalize() {
        synthesisIntervalMinutes = min(30, max(1, synthesisIntervalMinutes))
        retentionDays = min(3650, max(1, retentionDays))
        version = Self.currentVersion
        notesProviderID = Self.normalizedIdentifier(notesProviderID, maximum: 64)
        notesModelID = Self.normalizedIdentifier(notesModelID, maximum: 192)
        sttProviderID = Self.normalizedIdentifier(sttProviderID, maximum: 64)
        sttModelID = Self.normalizedIdentifier(sttModelID, maximum: 192)
        sttRegionID = Self.normalizedIdentifier(sttRegionID, maximum: 64)
        if let snapshot = sttEndpointSnapshot,
           snapshot.profileID != sttEndpointProfileID || snapshot.providerID != sttProviderID
        {
            sttEndpointSnapshot = nil
            sttEndpointProfileID = nil
        }
        if let metadata = sttModelMetadata, metadata.id != sttModelID || !metadata.modes.contains(sttMode) {
            sttModelMetadata = nil
        }
        sttLanguageCodes = Array(Set(sttLanguageCodes.filter(MeetingTranscriptionValidation.isValidLanguageCode))).sorted().prefix(16)
            .map(\.self)
        sttKeyterms = Self.normalizedKeyterms(sttKeyterms)
        if let sttMaximumSpeakers {
            self.sttMaximumSpeakers = min(32, max(1, sttMaximumSpeakers))
        }
        sttProviderOptions.normalize()
        sttProviderOptions.transcriptTTLHours = nil
        sttProviderOptions.trainingOptOutEnabled = sttAccountAttestations.contains {
            $0.kind == .assemblyAITrainingOptOut && $0.isExact
        }
        if sttRetention == .transient {
            sttRetention = sttMode == .localChunked ? .none : .providerDefault
        }
        if sttEndpointSnapshot?.source == .custom {
            sttRetention = .configurable
        }
        sttAccountAttestations = Dictionary(
            uniqueKeysWithValues: sttAccountAttestations.filter(\.isExact).map { ($0.kind, $0) }
        ).values.sorted { $0.kind.rawValue < $1.kind.rawValue }
        styleInstructions = String(styleInstructions.replacingOccurrences(of: "\0", with: "").prefix(2000))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard 1 ... Self.currentVersion ~= decodedVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        version = Self.currentVersion
        synthesisIntervalMinutes = try container.decode(Int.self, forKey: .synthesisIntervalMinutes)
        includeSystemAudio = try container.decode(Bool.self, forKey: .includeSystemAudio)
        includeMicrophone = try container.decode(Bool.self, forKey: .includeMicrophone)
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
        sttProviderID = try container.decodeIfPresent(String.self, forKey: .sttProviderID)
            ?? Self.defaults.sttProviderID
        sttModelID = try container.decodeIfPresent(String.self, forKey: .sttModelID)
            ?? Self.defaults.sttModelID
        sttMode = try container.decodeIfPresent(MeetingTranscriptionMode.self, forKey: .sttMode)
            ?? Self.defaults.sttMode
        sttRegionID = try container.decodeIfPresent(String.self, forKey: .sttRegionID)
            ?? Self.defaults.sttRegionID
        sttCredentialProfileID = try container.decodeIfPresent(UUID.self, forKey: .sttCredentialProfileID)
        sttEndpointProfileID = try container.decodeIfPresent(UUID.self, forKey: .sttEndpointProfileID)
        sttEndpointSnapshot = try container.decodeIfPresent(MeetingTranscriptionEndpointSnapshot.self, forKey: .sttEndpointSnapshot)
        sttModelMetadata = try container.decodeIfPresent(MeetingDiscoveredTranscriptionModel.self, forKey: .sttModelMetadata)
        sttLanguageCodes = try container.decodeIfPresent([String].self, forKey: .sttLanguageCodes) ?? []
        sttDiarizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .sttDiarizationEnabled) ?? false
        sttRetention = try container.decodeIfPresent(MeetingTranscriptionDataRetentionClass.self, forKey: .sttRetention)
            ?? .none
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
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(synthesisIntervalMinutes, forKey: .synthesisIntervalMinutes)
        try container.encode(includeSystemAudio, forKey: .includeSystemAudio)
        try container.encode(includeMicrophone, forKey: .includeMicrophone)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(shareProjectContext, forKey: .shareProjectContext)
        try container.encode(contextScope, forKey: .contextScope)
        try container.encode(notesProviderID, forKey: .notesProviderID)
        try container.encode(notesModelID, forKey: .notesModelID)
        try container.encode(styleInstructions, forKey: .styleInstructions)
        try container.encode(sttProviderID, forKey: .sttProviderID)
        try container.encode(sttModelID, forKey: .sttModelID)
        try container.encode(sttMode, forKey: .sttMode)
        try container.encode(sttRegionID, forKey: .sttRegionID)
        try container.encodeIfPresent(sttEndpointProfileID, forKey: .sttEndpointProfileID)
        try container.encodeIfPresent(sttEndpointSnapshot, forKey: .sttEndpointSnapshot)
        try container.encodeIfPresent(sttModelMetadata, forKey: .sttModelMetadata)
        try container.encodeIfPresent(sttCredentialProfileID, forKey: .sttCredentialProfileID)
        try container.encode(sttLanguageCodes, forKey: .sttLanguageCodes)
        try container.encode(sttDiarizationEnabled, forKey: .sttDiarizationEnabled)
        try container.encode(sttRetention, forKey: .sttRetention)
        try container.encode(sttKeyterms, forKey: .sttKeyterms)
        try container.encodeIfPresent(sttMaximumSpeakers, forKey: .sttMaximumSpeakers)
        try container.encode(sttProviderOptions, forKey: .sttProviderOptions)
        try container.encode(sttAccountAttestations, forKey: .sttAccountAttestations)
        try container.encode(localFallbackEnabled, forKey: .localFallbackEnabled)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case synthesisIntervalMinutes
        case includeSystemAudio
        case includeMicrophone
        case retentionDays
        case shareProjectContext
        case contextScope
        case notesProviderID
        case notesModelID
        case providerID
        case modelID
        case styleInstructions
        case sttProviderID
        case sttModelID
        case sttMode
        case sttRegionID
        case sttCredentialProfileID
        case sttEndpointProfileID
        case sttEndpointSnapshot
        case sttModelMetadata
        case sttLanguageCodes
        case sttDiarizationEnabled
        case sttRetention
        case sttKeyterms
        case sttMaximumSpeakers
        case sttProviderOptions
        case sttAccountAttestations
        case localFallbackEnabled
    }

    private static func normalizedKeyterms(_ values: [String]) -> [String] {
        var result: [String] = []
        var bytes = 0
        for value in values {
            let normalized = value.replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 200, !result.contains(normalized) else { continue }
            let nextBytes = bytes + normalized.utf8.count
            guard result.count < 100, nextBytes <= 10000 else { break }
            result.append(normalized)
            bytes = nextBytes
        }
        return result
    }

    private static func normalizedIdentifier(_ value: String, maximum: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.filter { character in
            character.asciiValue.map { $0 >= 0x21 && $0 <= 0x7E } ?? false
        }
        return String(filtered.prefix(maximum))
    }

    private var disclosureClaims: [String] {
        var claims = [
            "Transcripts and generated notes are retained locally for up to \(retentionDays) days.",
            "Pinned meeting sessions do not expire until they are unpinned or explicitly deleted.",
        ]
        if sttMode != .localChunked, let endpoint = sttEndpointSnapshot {
            claims.append("Raw meeting audio is sent to \(rawAudioRecipient) using the \(endpoint.variant.rawValue) protocol.")
            if endpoint.source == .custom {
                claims.append("The custom endpoint operator controls processing and retention; provider-hosted guarantees are unverified.")
            }
        } else {
            claims.append("Meeting audio transcription remains on this Mac.")
        }
        if shareProjectContext {
            claims.append(
                "Shared project metadata may include project names, worktree names, branch names, and safe relative changed-file paths."
            )
        } else {
            claims.append("Project metadata sharing is disabled.")
        }
        claims.append(contentsOf: sttAccountAttestations.map(\.claim))
        return claims
    }
}

@MainActor
@Observable
final class MeetingNotesSettingsStore {
    static let shared = MeetingNotesSettingsStore()
    private static let maximumSettingsBytes = 128 * 1024
    private static let persistenceErrorMessage = "Meeting notes settings could not be loaded or saved."

    private(set) var settings: MeetingNotesIntegrationSettings
    private(set) var persistenceError: String?
    private(set) var allowingDestructiveRetention: Bool

    @ObservationIgnored private let fileURL: URL

    init(
        fileStore: CodableFileStore<MeetingNotesIntegrationSettings> = .init(
            fileURL: KajiFileStorage.fileURL(filename: "meeting-notes-settings.json"),
            options: .prettySorted
        )
    ) {
        fileURL = fileStore.fileURL
        settings = .defaults
        allowingDestructiveRetention = false
        load()
        if persistenceError == nil { repairTranscriptionSelection() }
    }

    var isModelConfigured: Bool { settings.isModelConfigured }
    var unavailableReason: String? { isModelConfigured ? nil : "Choose a meeting notes provider and model." }

    func update(_ transform: (inout MeetingNotesIntegrationSettings) -> Void) {
        var next = settings
        transform(&next)
        next.normalize()
        settings = next
        repairTranscriptionSelection()
        persist()
    }

    func configureModel(providerID: String, modelID: String) {
        update {
            $0.notesProviderID = providerID
            $0.notesModelID = modelID
        }
    }

    private func repairTranscriptionSelection() {
        if settings.sttEndpointSnapshot == nil,
           let profile = MeetingTranscriptionEndpointStore.shared.defaultProfile(
               providerID: settings.sttProviderID,
               regionID: settings.sttRegionID
           )
        {
            settings.sttEndpointProfileID = profile.id
            settings.sttEndpointSnapshot = profile.snapshot
        }
        if settings.sttProviderID == FluidAudioMeetingTranscriptionProvider.providerID,
           settings.sttModelID.isEmpty,
           let model = SpeechModelRegistryStore.shared.models.first
        {
            settings.sttModelID = model.id
            settings.sttModelMetadata = try? MeetingDiscoveredTranscriptionModel(
                id: model.id,
                displayName: model.title,
                modes: [.localChunked],
                capabilityConfidence: .providerReported,
                metadata: ["processing": "local"]
            )
        }
    }

    func reset() {
        settings = .defaults
        persist()
    }

    func flush() {
        persist()
    }

    private func persist() {
        do {
            let data = try encoded(settings)
            try writeSecurely(data, to: fileURL)
            try writeSecurely(data, to: backupURL)
            persistenceError = nil
            allowingDestructiveRetention = true
        } catch {
            persistenceError = Self.persistenceErrorMessage
            allowingDestructiveRetention = false
        }
    }

    private var backupURL: URL {
        fileURL.appendingPathExtension("backup")
    }

    private func load() {
        do {
            try secureParentDirectory()
            if !itemExists(fileURL), !itemExists(backupURL) {
                settings = .defaults
                persistenceError = nil
                allowingDestructiveRetention = true
                return
            }
            if itemExists(fileURL), let loaded = try? loadSettings(from: fileURL) {
                settings = loaded
                var failed = false
                do {
                    try setSecureFilePermissions(fileURL)
                } catch {
                    failed = true
                }
                do {
                    try writeSecurely(encoded(settings), to: backupURL)
                } catch {
                    failed = true
                }
                if failed {
                    persistenceError = Self.persistenceErrorMessage
                    allowingDestructiveRetention = false
                } else {
                    persistenceError = nil
                    allowingDestructiveRetention = true
                }
                return
            }
            settings = try loadSettings(from: backupURL)
            persistenceError = Self.persistenceErrorMessage
            var failed = false
            do {
                try writeSecurely(encoded(settings), to: fileURL)
            } catch {
                failed = true
            }
            do {
                try setSecureFilePermissions(backupURL)
            } catch {
                failed = true
            }
            allowingDestructiveRetention = !failed
        } catch {
            settings = .defaults
            persistenceError = Self.persistenceErrorMessage
            allowingDestructiveRetention = false
        }
    }

    private func loadSettings(from url: URL) throws -> MeetingNotesIntegrationSettings {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumSettingsBytes
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var loaded = try JSONDecoder().decode(MeetingNotesIntegrationSettings.self, from: data)
        loaded.normalize()
        return loaded
    }

    private func encoded(_ value: MeetingNotesIntegrationSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumSettingsBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        return data
    }

    private func writeSecurely(_ data: Data, to url: URL) throws {
        try secureParentDirectory()
        if itemExists(url) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        try data.write(to: url, options: .atomic)
        try setSecureFilePermissions(url)
    }

    private func secureParentDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if itemExists(directory) {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw CocoaError(.fileWriteNoPermission)
            }
        } else {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func setSecureFilePermissions(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}
