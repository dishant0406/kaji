import Foundation
import os

enum MeetingNotesCoordinatorStatus: Equatable {
    case unconfigured
    case loading
    case idle
    case preparing
    case choosingApplication
    case starting
    case recording
    case stopping
    case synthesizing
    case completed
    case unavailable(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loading,
             .preparing,
             .choosingApplication,
             .starting,
             .stopping,
             .synthesizing:
            true
        case .unconfigured,
             .idle,
             .recording,
             .completed,
             .unavailable,
             .failed:
            false
        }
    }
}

struct MeetingNotesCoordinatorIssue: Identifiable, Equatable {
    enum Kind: String {
        case persistence
        case capture
        case transcription
        case synthesis
        case recovery
    }

    let id: UUID
    let kind: Kind
    let occurredAtMilliseconds: Int64
    let message: String
}

struct MeetingTranscriptionTrackHealth: Equatable {
    let providerEpoch: MeetingProviderEpoch
    let state: MeetingTranscriptionTrackRuntimeState
    let updatedAtMilliseconds: Int64
    let code: String?
}

enum MeetingNotesCoordinatorError: LocalizedError, Equatable {
    case notConfigured
    case operationInProgress
    case noAudioSource
    case transcriptionProviderUnavailable
    case sessionNotFound
    case activeSessionProtected
    case invalidUserEdit
    case invalidConsent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Meeting notes are not configured."
        case .operationInProgress:
            "A meeting operation is already in progress."
        case .noAudioSource:
            "Enable microphone or system audio before recording."
        case .transcriptionProviderUnavailable:
            "The selected transcription provider is not ready."
        case .sessionNotFound:
            "The meeting could not be found."
        case .activeSessionProtected:
            "Stop the active meeting before changing it."
        case .invalidUserEdit:
            "The meeting note edit is invalid."
        case .invalidConsent:
            "Review the recording disclosure and provide fresh consent before recording."
        }
    }
}

enum MeetingNoteItemReference: Equatable {
    case decision(UUID)
    case actionItem(UUID)
    case openQuestion(UUID)
    case risk(UUID)
}

@MainActor
@Observable
final class MeetingNotesCoordinator {
    static let shared = MeetingNotesCoordinator()

    private(set) var sessions: [MeetingSession] = []
    private(set) var activeDocument: MeetingSessionDocument?
    private(set) var selectedDocument: MeetingSessionDocument?
    private(set) var status: MeetingNotesCoordinatorStatus = .unconfigured
    private(set) var elapsedDuration: TimeInterval = 0
    private(set) var issues: [MeetingNotesCoordinatorIssue] = []
    private(set) var partialTranscriptSegments: [UUID: MeetingTranscriptSegment] = [:]
    private(set) var transcriptionReadiness: MeetingTranscriptionReadiness = .unavailable
    private(set) var transcriptionTrackHealth: [UUID: MeetingTranscriptionTrackHealth] = [:]
    private(set) var transcriptionUsage: [String: Int64] = [:]
    private(set) var transcriptionRateLimitWarning: String?
    private(set) var transcriptionWarnings: [String] = []
    private(set) var notesModelReadiness: MeetingNotesModelReadiness = .unchecked

    @ObservationIgnored private let store: any MeetingSessionPersisting
    @ObservationIgnored private let settingsStore: MeetingNotesSettingsStore
    @ObservationIgnored private let picker: any MeetingContentPicking
    @ObservationIgnored private let runtimeFactory: any MeetingRecordingRuntimeBuilding
    @ObservationIgnored private let transcriptionResolver: any MeetingTranscriptionProviderResolving
    @ObservationIgnored private let synthesizer: any MeetingNotesSynthesizing
    @ObservationIgnored private let notesModelValidator: any MeetingNotesModelValidating
    @ObservationIgnored private let clock: any MeetingClock
    @ObservationIgnored private let reducer: MeetingNotesReducer
    @ObservationIgnored private var contextProvider: (any MeetingProjectContextProviding)?
    @ObservationIgnored private var documents: [UUID: MeetingSessionDocument] = [:]
    @ObservationIgnored private var runtime: MeetingRecordingRuntime?
    @ObservationIgnored private var elapsedTask: Task<Void, Never>?
    @ObservationIgnored private var synthesisTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var synthesisOperationTask: Task<MeetingNotesPatch, Error>?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var startupGeneration: UUID?
    @ObservationIgnored private var lifecycleGeneration: UUID?
    @ObservationIgnored private var synthesisInFlight = false
    @ObservationIgnored private var interruptionReason: String?
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var issuedConsents: [UUID: MeetingSessionConfiguration] = [:]
    @ObservationIgnored private var pendingConsent: MeetingRecordingConsent?

    private let logger = Logger(subsystem: "app.kaji", category: "MeetingNotesCoordinator")

    init(
        store: any MeetingSessionPersisting = MeetingSessionStore(),
        settingsStore: MeetingNotesSettingsStore = .shared,
        picker: any MeetingContentPicking = MeetingContentSharingPicker(),
        runtimeFactory: any MeetingRecordingRuntimeBuilding = DefaultMeetingRecordingRuntimeFactory(),
        transcriptionResolver: any MeetingTranscriptionProviderResolving = MeetingTranscriptionProviderCatalog.shared,
        synthesizer: any MeetingNotesSynthesizing = KajiMeetingNotesAgentClient(),
        notesModelValidator: (any MeetingNotesModelValidating)? = nil,
        clock: any MeetingClock = SystemMeetingClock(),
        reducer: MeetingNotesReducer = MeetingNotesReducer(),
        contextProvider: (any MeetingProjectContextProviding)? = nil
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.picker = picker
        self.runtimeFactory = runtimeFactory
        self.transcriptionResolver = transcriptionResolver
        self.synthesizer = synthesizer
        self.notesModelValidator = notesModelValidator ?? KajiMeetingNotesAgentClient()
        self.clock = clock
        self.reducer = reducer
        self.contextProvider = contextProvider
        status = contextProvider == nil ? .unconfigured : .idle
    }

    var recordingGaps: [MeetingRecordingGap] {
        activeDocument?.recordingGaps ?? selectedDocument?.recordingGaps ?? []
    }

    var requiresTerminationDrain: Bool {
        startupTask != nil || activeDocument != nil || runtime != nil
    }

    func configure(appState: AppState, projectStore: ProjectStore, worktreeStore: WorktreeStore) {
        contextProvider = MeetingProjectContextProvider(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        if status == .unconfigured {
            status = .idle
        }
    }

    func makeRecordingConsent() -> MeetingRecordingConsent {
        let configuration = settingsStore.settings.sessionConfiguration(consentedAtMilliseconds: clock.nowMilliseconds())
        let consent = MeetingRecordingConsent(id: UUID(), configuration: configuration)
        issuedConsents[consent.id] = configuration
        if issuedConsents.count > 100, let oldest = issuedConsents.min(by: {
            $0.value.consentedAtMilliseconds < $1.value.consentedAtMilliseconds
        }) {
            issuedConsents.removeValue(forKey: oldest.key)
        }
        return consent
    }

    func authorizeNextStart(with consent: MeetingRecordingConsent) {
        pendingConsent = consent
    }

    func refreshTranscriptionReadiness() async {
        let configuration = settingsStore.settings.sessionConfiguration(
            consentedAtMilliseconds: clock.nowMilliseconds()
        )
        do {
            let resolved = try transcriptionResolver.resolve(configuration: configuration)
            transcriptionReadiness = await resolved.provider.readiness(for: resolved.route)
        } catch {
            transcriptionReadiness = (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The selected transcription route requires configuration."
            )) ?? .unavailable
        }
    }

    func refreshNotesModelReadiness() async {
        let settings = settingsStore.settings
        guard settings.isModelConfigured else {
            notesModelReadiness = .unchecked
            return
        }
        notesModelReadiness = .checking
        notesModelReadiness = await notesModelValidator.validateModel(
            providerID: settings.notesProviderID,
            modelID: settings.notesModelID
        )
    }

    func prepare() async {
        guard contextProvider != nil else {
            status = .unconfigured
            return
        }
        guard !isPrepared else { return }
        status = .loading
        let now = clock.nowMilliseconds()
        do {
            let recovered = try await store.recoverStaleSessions(
                nowMilliseconds: now,
                staleAfterMilliseconds: 0,
                reason: "Recording was interrupted before the session completed."
            )
            if !recovered.isEmpty {
                appendIssue(.recovery, message: "Interrupted meetings were recovered.")
            }
            if settingsStore.allowingDestructiveRetention {
                _ = try await store.enforceRetention(
                    settings: settingsStore.settings.persistenceSettings,
                    nowMilliseconds: now
                )
            }
            let result = try await store.load()
            var loadedDocuments = result.documents
            for index in loadedDocuments.indices where !loadedDocuments[index].configuration.isModelConfigured {
                loadedDocuments[index].synthesisState.pendingSegmentIDs.removeAll()
                loadedDocuments[index].synthesisState.status = .completed
                loadedDocuments[index].synthesisState.nextAttemptAtMilliseconds = nil
                loadedDocuments[index].synthesisState.lastErrorCode = nil
            }
            documents = Dictionary(uniqueKeysWithValues: loadedDocuments.map { ($0.session.id, $0) })
            for document in loadedDocuments where !document.configuration.isModelConfigured {
                do {
                    try await store.save(document)
                } catch {
                    appendIssue(.persistence, message: "A meeting synthesis cursor could not be updated.")
                }
            }
            refreshSessions()
            if !result.issues.isEmpty {
                appendIssue(.persistence, message: "Some meeting records could not be loaded.")
            }
            isPrepared = true
            status = .idle
            for document in loadedDocuments where document.session.lifecycle.phase.isTerminal &&
                document.configuration.isModelConfigured && document.synthesisState.isPending
            {
                await scheduleSynthesisIfNeeded(
                    sessionID: document.session.id,
                    generation: nil,
                    minimumDelayMilliseconds: 30000
                )
            }
        } catch {
            appendIssue(.persistence, message: "Meeting records could not be loaded.")
            status = .failed("Meeting records could not be loaded.")
        }
    }

    func start(title: String = "Meeting") async {
        let consent = pendingConsent
        pendingConsent = nil
        guard let consent else {
            status = .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription)
            return
        }
        await start(title: title, consent: consent)
    }

    func start(title: String = "Meeting", consent: MeetingRecordingConsent) async {
        if let startupTask {
            await startupTask.value
            return
        }
        guard stopTask == nil, activeDocument == nil, !status.isBusy else {
            status = .failed(MeetingNotesCoordinatorError.operationInProgress.localizedDescription)
            return
        }
        guard consume(consent) else {
            status = .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription)
            return
        }
        guard contextProvider != nil else {
            status = .unconfigured
            return
        }
        if !isPrepared {
            await prepare()
        }
        guard isPrepared else { return }
        let generation = UUID()
        startupGeneration = generation
        lifecycleGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performStart(title: title, configuration: consent.configuration, generation: generation)
        }
        startupTask = task
        await task.value
        if startupGeneration == generation {
            startupTask = nil
            startupGeneration = nil
        }
    }

    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard startupTask != nil || activeDocument != nil || runtime != nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performStop()
        }
        stopTask = task
        await task.value
        stopTask = nil
    }

    func retrySynthesis(sessionID: UUID) async {
        guard startupTask == nil,
              stopTask == nil,
              !synthesisInFlight,
              var document = documents[sessionID],
              document.synthesisState.isPending,
              document.session.lifecycle.phase.isTerminal || activeDocument?.session.id == sessionID
        else {
            return
        }
        guard document.configuration.isModelConfigured else {
            appendIssue(.synthesis, message: "This meeting has no configured notes model to retry.")
            return
        }
        await cancelSynthesisTask(sessionID: sessionID)
        document.synthesisState.status = .scheduled
        document.synthesisState.nextAttemptAtMilliseconds = nil
        document.synthesisState.lastErrorCode = nil
        publishDocument(document, asActive: activeDocument?.session.id == sessionID)
        try? await store.save(document)
        let previousStatus = status
        status = .synthesizing
        let generation = activeDocument?.session.id == sessionID ? lifecycleGeneration : nil
        _ = await synthesizeBatch(sessionID: sessionID, generation: generation)
        if status == .synthesizing {
            status = previousStatus == .synthesizing ? .completed : previousStatus
        }
        if let current = documents[sessionID],
           current.synthesisState.isPending,
           current.synthesisState.lastErrorCode?.allowsAutomaticRetry != false
        {
            await scheduleSynthesisIfNeeded(sessionID: sessionID, generation: generation)
        }
    }

    func hasPendingSynthesis(sessionID: UUID) -> Bool {
        guard let document = documents[sessionID], document.configuration.isModelConfigured else { return false }
        return document.synthesisState.isPending
    }

    func delete(sessionID: UUID, includingPinned: Bool = false) async {
        guard activeDocument?.session.id != sessionID else {
            status = .failed(MeetingNotesCoordinatorError.activeSessionProtected.localizedDescription)
            return
        }
        do {
            guard try await store.deleteSession(id: sessionID, includingPinned: includingPinned) else { return }
            documents.removeValue(forKey: sessionID)
            if selectedDocument?.session.id == sessionID {
                selectedDocument = nil
            }
            refreshSessions()
        } catch {
            appendIssue(.persistence, message: "The meeting could not be deleted.")
            status = .failed("The meeting could not be deleted.")
        }
    }

    func select(sessionID: UUID?) {
        guard let sessionID else {
            selectedDocument = nil
            return
        }
        selectedDocument = documents[sessionID]
    }

    func pin(sessionID: UUID, isPinned: Bool) async {
        guard activeDocument?.session.id != sessionID, var document = documents[sessionID] else {
            status = .failed(MeetingNotesCoordinatorError.activeSessionProtected.localizedDescription)
            return
        }
        document.session.isPinned = isPinned
        try? document.session.touch(atMilliseconds: max(clock.nowMilliseconds(), document.session.updatedAtMilliseconds))
        await saveUpdatedDocument(document)
    }

    func pin(sessionID: UUID, item: MeetingNoteItemReference, isPinned: Bool) async {
        guard var document = documents[sessionID] else { return }
        switch item {
        case let .decision(id):
            guard let index = document.notes.decisions.firstIndex(where: { $0.id == id }) else { return }
            document.notes.decisions[index].isPinned = isPinned
        case let .actionItem(id):
            guard let index = document.notes.actionItems.firstIndex(where: { $0.id == id }) else { return }
            document.notes.actionItems[index].isPinned = isPinned
        case let .openQuestion(id):
            guard let index = document.notes.openQuestions.firstIndex(where: { $0.id == id }) else { return }
            document.notes.openQuestions[index].isPinned = isPinned
        case let .risk(id):
            guard let index = document.notes.risks.firstIndex(where: { $0.id == id }) else { return }
            document.notes.risks[index].isPinned = isPinned
        }
        let now = max(clock.nowMilliseconds(), document.notes.updatedAtMilliseconds)
        document.notes.revision += 1
        document.notes.updatedAtMilliseconds = now
        document.noteRevisions.append(MeetingNotesRevision(
            id: UUID(),
            patchID: UUID(),
            baseRevision: document.notes.revision - 1,
            resultingRevision: document.notes.revision,
            createdAtMilliseconds: now,
            source: .userEdit
        ))
        await saveUpdatedDocument(document)
    }

    func updateUserNote(_ patch: MeetingNotesPatch) async {
        guard var document = documents[patch.sessionID],
              !patch.operations.isEmpty
        else {
            status = .failed(MeetingNotesCoordinatorError.invalidUserEdit.localizedDescription)
            return
        }
        do {
            let now = max(clock.nowMilliseconds(), document.notes.updatedAtMilliseconds)
            let updated = try reducer.applying(
                patch,
                to: document.notes,
                transcriptSegments: document.transcriptSegments,
                allowedProjectIDs: Set(document.session.projectIDs),
                atMilliseconds: now
            )
            document.notes = updated
            document.session.title = updated.title
            try document.session.touch(atMilliseconds: max(now, document.session.updatedAtMilliseconds))
            document.noteRevisions.append(MeetingNotesRevision(
                id: UUID(),
                patchID: patch.id,
                baseRevision: patch.baseRevision,
                resultingRevision: updated.revision,
                createdAtMilliseconds: now,
                source: .userEdit
            ))
            await saveUpdatedDocument(document)
        } catch {
            status = .failed(MeetingNotesCoordinatorError.invalidUserEdit.localizedDescription)
        }
    }

    func shutdownForTermination() async -> Bool {
        if startupTask != nil || activeDocument != nil {
            interruptionReason = "The application terminated while recording."
            await stop()
        }
        settingsStore.flush()
        return startupTask == nil && activeDocument == nil && runtime == nil
    }

    func flushForTermination() async {
        if let document = activeDocument ?? selectedDocument {
            try? await store.save(document)
        }
        settingsStore.flush()
    }

    private func performStart(
        title: String,
        configuration: MeetingSessionConfiguration,
        generation: UUID
    ) async {
        guard configuration.includeSystemAudio || configuration.includeMicrophone else {
            lifecycleGeneration = nil
            status = .unavailable(MeetingNotesCoordinatorError.noAudioSource.localizedDescription)
            return
        }
        status = .preparing
        let transcription: MeetingResolvedTranscriptionProvider
        do {
            transcription = try transcriptionResolver.resolve(configuration: configuration)
        } catch {
            lifecycleGeneration = nil
            transcriptionReadiness = (try? MeetingTranscriptionReadiness(
                state: .requiresConfiguration,
                reason: "The selected transcription route requires configuration."
            )) ?? .unavailable
            status = .unavailable(MeetingNotesCoordinatorError.transcriptionProviderUnavailable.localizedDescription)
            return
        }
        transcriptionReadiness = await transcription.provider.readiness(for: transcription.route)
        guard transcriptionReadiness.state == .ready else {
            lifecycleGeneration = nil
            status = .unavailable(
                transcriptionReadiness.reason
                    ?? MeetingNotesCoordinatorError.transcriptionProviderUnavailable.localizedDescription
            )
            return
        }
        status = .choosingApplication
        let selection: MeetingContentSelection
        do {
            selection = try await picker.selectApplication()
        } catch MeetingContentPickerError.cancelled {
            finishCancelledStart(generation: generation)
            return
        } catch is CancellationError {
            finishCancelledStart(generation: generation)
            return
        } catch {
            guard startupIsCurrent(generation) else {
                finishCancelledStart(generation: generation)
                return
            }
            lifecycleGeneration = nil
            status = .failed("Application selection failed.")
            return
        }
        guard startupIsCurrent(generation) else {
            finishCancelledStart(generation: generation)
            return
        }
        guard consentIsCurrent(configuration) else {
            lifecycleGeneration = nil
            status = .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription)
            return
        }
        status = .starting
        let now = clock.nowMilliseconds()
        do {
            let projectIDs = configuration.shareProjectContext
                ? contextProvider?.projectIDs(scope: configuration.contextScope) ?? []
                : []
            var session = try MeetingSession(
                title: normalizedTitle(title),
                projectIDs: Array(projectIDs.prefix(20)),
                createdAtMilliseconds: now
            )
            let systemSource = try configuration.includeSystemAudio ? MeetingAudioSourceIdentity(
                trackID: UUID(),
                kind: .systemAudio,
                displayName: "Selected application audio",
                startedAtMilliseconds: now
            ) : nil
            let microphoneSource = try configuration.includeMicrophone ? MeetingAudioSourceIdentity(
                trackID: UUID(),
                kind: .microphone,
                displayName: "Microphone",
                startedAtMilliseconds: now
            ) : nil
            try session.transition(to: .recording, atMilliseconds: now)
            let document = MeetingSessionDocument(
                session: session,
                tracks: [systemSource?.track, microphoneSource?.track].compactMap(\.self),
                configuration: configuration
            )
            publishDocument(document, asActive: true)
            try await store.save(document)
            guard startupIsCurrent(generation) else { return }
            let runtime = try runtimeFactory.makeRuntime(
                selection: selection,
                sessionID: session.id,
                transcription: transcription,
                sources: MeetingRecordingSources(
                    systemAudio: systemSource,
                    microphone: microphoneSource
                )
            ) { [weak self] event in
                await self?.handlePipelineEvent(event, generation: generation)
            }
            self.runtime = runtime
            await runtime.pipeline.start()
            guard startupIsCurrent(generation) else { return }
            guard consentIsCurrent(configuration) else {
                interruptionReason = MeetingNotesCoordinatorError.invalidConsent.localizedDescription
                await finishActiveSession(interrupted: true)
                return
            }
            do {
                try await runtime.capture.start()
            } catch {
                guard startupIsCurrent(generation) else { return }
                interruptionReason = "Audio capture could not start."
                appendIssue(.capture, message: "Audio capture could not start.")
                await finishActiveSession(interrupted: true)
                return
            }
            guard startupIsCurrent(generation) else { return }
            status = .recording
            startElapsedUpdates(startedAtMilliseconds: now)
        } catch {
            guard startupIsCurrent(generation) else { return }
            appendIssue(.persistence, message: "The meeting could not be started.")
            if activeDocument != nil {
                interruptionReason = "The meeting could not be started."
                await finishActiveSession(interrupted: true)
            } else {
                lifecycleGeneration = nil
                status = .failed("The meeting could not be started.")
            }
        }
    }

    private func performStop() async {
        status = .stopping
        startupGeneration = nil
        startupTask?.cancel()
        picker.cancel()
        if let startupTask {
            await startupTask.value
        }
        self.startupTask = nil
        await cancelPeriodicSynthesis()
        if activeDocument != nil {
            await finishActiveSession(interrupted: interruptionReason != nil)
            return
        }
        await drainRuntime()
        lifecycleGeneration = nil
        if status == .stopping {
            status = .idle
        }
    }

    private func handlePipelineEvent(_ event: MeetingAudioPipelineEvent, generation: UUID) async {
        guard lifecycleGeneration == generation, var document = activeDocument else { return }
        switch event {
        case let .partialTranscript(segment):
            guard let segment = validatedTranscript(segment, in: document) else { return }
            partialTranscriptSegments[segment.id] = segment
        case let .transcript(segment):
            guard let segment = validatedTranscript(segment, in: document), appendTranscript(segment, to: &document) else {
                return
            }
            partialTranscriptSegments.removeValue(forKey: segment.id)
            if document.configuration.isModelConfigured {
                document.synthesisState.pendingSegmentIDs.insert(segment.id)
                if document.synthesisState.status != .failed {
                    document.synthesisState.status = .scheduled
                }
            } else {
                document.synthesisState.pendingSegmentIDs.removeAll()
                document.synthesisState.status = .completed
            }
            try? document.session.touch(atMilliseconds: max(segment.createdAtMilliseconds, document.session.updatedAtMilliseconds))
            publishDocument(document, asActive: true)
            do {
                try await store.save(document)
            } catch {
                appendIssue(.persistence, message: "A transcript update could not be saved.")
            }
            await scheduleSynthesisIfNeeded(sessionID: document.session.id, generation: generation)
        case let .committedMetadata(metadata):
            guard document.transcriptSegments.contains(where: { $0.id == metadata.id && $0.isFinal }) else { return }
            document.committedTranscriptMetadata.removeAll { $0.id == metadata.id }
            document.committedTranscriptMetadata.append(metadata)
            publishDocument(document, asActive: true)
            try? await store.save(document)
        case let .metadataAmendment(metadata):
            guard let segmentIndex = document.transcriptSegments.firstIndex(where: { $0.id == metadata.id && $0.isFinal }),
                  let metadataIndex = document.committedTranscriptMetadata.firstIndex(where: { $0.id == metadata.id })
            else { return }
            let existing = document.transcriptSegments[segmentIndex]
            document.transcriptSegments[segmentIndex] = MeetingTranscriptSegment(
                id: existing.id,
                trackID: existing.trackID,
                sampleRange: existing.sampleRange,
                startMilliseconds: existing.startMilliseconds,
                endMilliseconds: existing.endMilliseconds,
                text: existing.text,
                speakerLabel: metadata.speaker?.label,
                isFinal: true,
                createdAtMilliseconds: existing.createdAtMilliseconds
            )
            document.committedTranscriptMetadata[metadataIndex] = metadata
            if document.configuration.isModelConfigured {
                document.synthesisState.synthesizedSegmentIDs.remove(metadata.id)
                document.synthesisState.pendingSegmentIDs.insert(metadata.id)
                if document.synthesisState.status != .failed {
                    document.synthesisState.status = .scheduled
                }
            }
            publishDocument(document, asActive: true)
            try? await store.save(document)
            await scheduleSynthesisIfNeeded(sessionID: document.session.id, generation: generation)
        case let .transcriptionUsage(usage):
            for metric in usage.metrics {
                transcriptionUsage[metric.billingUnit, default: 0] += metric.quantity
            }
        case let .transcriptionRateLimit(rateLimit):
            transcriptionRateLimitWarning = rateLimit.retryAfterMilliseconds.map {
                "Transcription rate limited. Retry in \($0) ms."
            } ?? "Transcription rate limit is approaching."
        case let .transcriptionWarning(warning):
            transcriptionWarnings.append(sanitizedWarning(code: warning.code))
            if transcriptionWarnings.count > 20 {
                transcriptionWarnings.removeFirst(transcriptionWarnings.count - 20)
            }
        case let .transcriptionSession(session):
            updateTrackHealth(
                MeetingTranscriptionTrackHealthRecord(
                    trackID: session.context.trackID,
                    providerEpoch: session.context.providerEpoch,
                    state: runtimeState(session.state),
                    updatedAtMilliseconds: session.context.emittedAtMilliseconds,
                    code: nil
                ),
                document: &document
            )
            publishDocument(document, asActive: true)
            try? await store.save(document)
        case let .transcriptionTrackHealth(health):
            updateTrackHealth(
                MeetingTranscriptionTrackHealthRecord(
                    trackID: health.trackID,
                    providerEpoch: health.providerEpoch,
                    state: health.state,
                    updatedAtMilliseconds: health.updatedAtMilliseconds,
                    code: health.code
                ),
                document: &document
            )
            publishDocument(document, asActive: true)
            try? await store.save(document)
        case .transcriptionFailure:
            appendIssue(.transcription, message: "Part of the meeting could not be transcribed.")
        case let .transcriptionFailureRange(failure, range):
            guard let track = document.tracks.first(where: { $0.id == failure.context.trackID }),
                  let sampleRange = try? MeetingSampleRange(
                      startFrame: range.startFrame,
                      endFrame: range.endFrame,
                      sampleRateHertz: range.sampleRateHertz
                  )
            else { return }
            let start = track.startedAtMilliseconds + range.startFrame * 1000 / Int64(range.sampleRateHertz)
            let end = track.startedAtMilliseconds + (range.endFrame * 1000 + Int64(range.sampleRateHertz) - 1)
                / Int64(range.sampleRateHertz)
            let gap = MeetingTranscriptionGap(
                id: UUID(),
                trackID: track.id,
                sampleRange: sampleRange,
                startMilliseconds: start,
                endMilliseconds: max(start + 1, end),
                classification: failure.classification,
                code: String(failure.code.prefix(128))
            )
            if !document.transcriptionGaps.contains(where: {
                $0.trackID == gap.trackID && $0.sampleRange == gap.sampleRange && $0.code == gap.code
            }) {
                document.transcriptionGaps.append(gap)
            }
            publishDocument(document, asActive: true)
            try? await store.save(document)
        case let .gap(gap):
            document.recordingGaps.append(MeetingRecordingGap(
                id: UUID(),
                trackID: gap.source.trackID,
                firstSequenceNumber: gap.firstSequenceNumber,
                lastSequenceNumber: gap.lastSequenceNumber,
                droppedBufferCount: gap.droppedBufferCount,
                droppedFrameCount: gap.droppedFrameCount,
                startMilliseconds: gap.startMilliseconds,
                endMilliseconds: gap.endMilliseconds,
                reason: String(gap.reason.rawValue.prefix(120))
            ))
            publishDocument(document, asActive: true)
            logger
                .warning("Meeting audio gap track=\(gap.source.trackID, privacy: .private(mask: .hash)) buffers=\(gap.droppedBufferCount)")
            try? await store.save(document)
        case let .failure(failure):
            let isPipelineFailure = failure.domain.hasPrefix("Kaji.MeetingAudio")
            appendIssue(
                isPipelineFailure ? .transcription : .capture,
                message: isPipelineFailure
                    ? "Part of the meeting could not be transcribed."
                    : "Meeting audio capture stopped unexpectedly."
            )
            logger.error("Meeting audio failure domain=\(failure.domain, privacy: .public) code=\(failure.code)")
            guard !isPipelineFailure else { return }
            interruptionReason = "Meeting audio capture stopped unexpectedly."
            Task { @MainActor [weak self] in await self?.stop() }
        }
    }

    private func validatedTranscript(
        _ segment: MeetingTranscriptSegment,
        in document: MeetingSessionDocument
    ) -> MeetingTranscriptSegment? {
        guard let track = document.tracks.first(where: { $0.id == segment.trackID }),
              segment.sampleRange.sampleRateHertz == track.sampleRateHertz,
              segment.sampleRange.startFrame >= 0,
              segment.sampleRange.endFrame > segment.sampleRange.startFrame,
              segment.startMilliseconds >= track.startedAtMilliseconds,
              segment.endMilliseconds > segment.startMilliseconds,
              segment.createdAtMilliseconds >= segment.startMilliseconds,
              segment.text.count <= 20000,
              (segment.speakerLabel?.count ?? 0) <= 120
        else {
            appendIssue(.transcription, message: "An invalid transcript segment was discarded.")
            return nil
        }
        let text = segment.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, !text.contains("\0") else {
            appendIssue(.transcription, message: "An empty transcript segment was discarded.")
            return nil
        }
        let speaker = segment.speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingTranscriptSegment(
            id: segment.id,
            trackID: segment.trackID,
            sampleRange: segment.sampleRange,
            startMilliseconds: segment.startMilliseconds,
            endMilliseconds: segment.endMilliseconds,
            text: text,
            speakerLabel: speaker?.isEmpty == true ? nil : speaker,
            isFinal: segment.isFinal,
            createdAtMilliseconds: segment.createdAtMilliseconds
        )
    }

    private func appendTranscript(_ segment: MeetingTranscriptSegment, to document: inout MeetingSessionDocument) -> Bool {
        guard !document.transcriptSegments.contains(where: { $0.id == segment.id }) else { return false }
        var canonical = segment
        if let previous = document.transcriptSegments
            .filter({ $0.trackID == segment.trackID && rangesOverlap($0, segment) })
            .max(by: MeetingTranscriptOrdering.areInIncreasingOrder)
        {
            canonical = MeetingTranscriptCanonicalizer.trimmingDuplicatePrefix(from: segment, after: previous)
        }
        guard !canonical.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let normalized = normalizedTranscript(canonical.text)
        let isDuplicate = document.transcriptSegments.contains { existing in
            existing.trackID == canonical.trackID &&
                rangesOverlap(existing, canonical) &&
                normalizedTranscript(existing.text) == normalized
        }
        guard !isDuplicate else { return false }
        document.transcriptSegments.append(canonical)
        document.transcriptSegments.sort(by: MeetingTranscriptOrdering.areInIncreasingOrder)
        return true
    }

    private func rangesOverlap(_ lhs: MeetingTranscriptSegment, _ rhs: MeetingTranscriptSegment) -> Bool {
        lhs.startMilliseconds < rhs.endMilliseconds && rhs.startMilliseconds < lhs.endMilliseconds
    }

    private func normalizedTranscript(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private func scheduleSynthesisIfNeeded(
        sessionID: UUID,
        generation: UUID?,
        minimumDelayMilliseconds: Int64? = nil
    ) async {
        guard synthesisTasks[sessionID] == nil,
              var document = documents[sessionID],
              document.synthesisState.isPending,
              document.configuration.isModelConfigured,
              document.synthesisState.lastErrorCode?.allowsAutomaticRetry != false
        else {
            return
        }
        let now = clock.nowMilliseconds()
        let configuredDelay = Int64(document.configuration.synthesisIntervalMinutes) * 60000
        let scheduledDelay = document.synthesisState.nextAttemptAtMilliseconds.map { max(0, $0 - now) }
        let delay = minimumDelayMilliseconds ?? scheduledDelay ?? configuredDelay
        if document.synthesisState.status != .retryScheduled {
            document.synthesisState.status = .scheduled
        }
        document.synthesisState.nextAttemptAtMilliseconds = now + delay
        publishDocument(document, asActive: activeDocument?.session.id == sessionID)
        try? await store.save(document)
        synthesisTasks[sessionID] = Task { @MainActor [weak self] in
            guard let self else { return }
            var result = SynthesisResult.failed
            do {
                try await clock.sleep(forMilliseconds: delay)
                guard !Task.isCancelled else { return }
                result = await synthesizeBatch(sessionID: sessionID, generation: generation)
            } catch {}
            let wasCancelled = Task.isCancelled
            synthesisTasks[sessionID] = nil
            guard !wasCancelled,
                  documents[sessionID]?.synthesisState.isPending == true
            else {
                return
            }
            if let generation {
                guard lifecycleGeneration == generation, activeDocument?.session.id == sessionID else { return }
            } else {
                guard documents[sessionID]?.session.lifecycle.phase.isTerminal == true else { return }
            }
            await scheduleSynthesisIfNeeded(
                sessionID: sessionID,
                generation: generation,
                minimumDelayMilliseconds: result == .busy ? 30000 : nil
            )
        }
    }

    private enum SynthesisResult {
        case succeeded
        case stale
        case failed
        case busy
    }

    private func synthesizeBatch(sessionID: UUID, generation: UUID?) async -> SynthesisResult {
        guard !synthesisInFlight else { return .busy }
        guard var document = documents[sessionID] else { return .failed }
        if let generation {
            guard lifecycleGeneration == generation, activeDocument?.session.id == sessionID else { return .failed }
        } else {
            guard document.session.lifecycle.phase.isTerminal else { return .failed }
        }
        let segments = document.transcriptSegments
            .filter { $0.isFinal && document.synthesisState.pendingSegmentIDs.contains($0.id) }
            .sorted(by: MeetingTranscriptOrdering.areInIncreasingOrder)
        guard !segments.isEmpty else {
            document.synthesisState.status = .completed
            document.synthesisState.nextAttemptAtMilliseconds = nil
            document.synthesisState.lastErrorCode = nil
            publishDocument(document, asActive: activeDocument?.session.id == sessionID)
            try? await store.save(document)
            return .succeeded
        }
        guard document.configuration.isModelConfigured else {
            await recordSynthesisFailure(.modelUnavailable, sessionID: sessionID)
            return .failed
        }
        let batch = Array(segments.prefix(128))
        let context = document.configuration.shareProjectContext
            ? contextProvider?.context(
                scope: document.configuration.contextScope,
                allowedProjectIDs: Set(document.session.projectIDs)
            )
            : nil
        let request = MeetingNotesSynthesisRequest(
            sessionID: sessionID,
            transcriptRevision: document.transcriptSegments.filter(\.isFinal).count,
            transcriptSegments: batch,
            currentNotes: document.notes,
            projectContext: context,
            sourceKindsByTrackID: Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, $0.kind) }),
            sourceLabelsByTrackID: Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, $0.displayName) }),
            providerID: document.configuration.notesProviderID,
            modelID: document.configuration.notesModelID,
            styleInstructions: document.configuration.styleInstructions,
            allowedProjectIDs: document.session.projectIDs
        )
        synthesisInFlight = true
        document.synthesisState.status = .generating
        document.synthesisState.attemptCount += 1
        document.synthesisState.lastAttemptAtMilliseconds = clock.nowMilliseconds()
        document.synthesisState.nextAttemptAtMilliseconds = nil
        document.synthesisState.lastErrorCode = nil
        publishDocument(document, asActive: activeDocument?.session.id == sessionID)
        try? await store.save(document)
        let previousStatus = status
        if previousStatus != .stopping {
            status = .synthesizing
        }
        let operation = Task { @MainActor in
            try await synthesizer.synthesizeNotes(for: request)
        }
        synthesisOperationTask = operation
        let response: Result<MeetingNotesPatch, Error> = await withTaskCancellationHandler {
            await operation.result
        } onCancel: {
            operation.cancel()
        }
        synthesisOperationTask = nil
        synthesisInFlight = false
        if status == .synthesizing {
            status = previousStatus == .recording ? .recording : previousStatus
        }
        guard !Task.isCancelled else {
            await recordSynthesisFailure(.cancelled, sessionID: sessionID)
            return .failed
        }
        if let generation {
            guard lifecycleGeneration == generation, activeDocument?.session.id == sessionID else { return .failed }
        } else {
            guard documents[sessionID]?.session.lifecycle.phase.isTerminal == true else { return .failed }
        }
        let patch: MeetingNotesPatch
        switch response {
        case let .success(value):
            patch = value
        case let .failure(error):
            let code = (error as? KajiMeetingNotesAgentError)?.synthesisCode ?? .providerFailure
            await recordSynthesisFailure(code, sessionID: sessionID)
            return .failed
        }
        guard var current = documents[sessionID] else { return .failed }
        guard current.notes.revision == request.currentNotes.revision else {
            current.synthesisState.status = .scheduled
            current.synthesisState.nextAttemptAtMilliseconds = nil
            publishDocument(current, asActive: activeDocument?.session.id == sessionID)
            try? await store.save(current)
            return .stale
        }
        guard patch.baseRevision == current.notes.revision else {
            await recordSynthesisFailure(.invalidResponse, sessionID: sessionID)
            return .failed
        }
        do {
            if !patch.operations.isEmpty {
                let now = max(clock.nowMilliseconds(), current.notes.updatedAtMilliseconds)
                let notes = try reducer.applying(
                    patch,
                    to: current.notes,
                    transcriptSegments: current.transcriptSegments,
                    allowedProjectIDs: Set(current.session.projectIDs),
                    atMilliseconds: now
                )
                current.notes = notes
                current.session.title = notes.title
                try current.session.touch(atMilliseconds: max(now, current.session.updatedAtMilliseconds))
                current.noteRevisions.append(MeetingNotesRevision(
                    id: UUID(),
                    patchID: patch.id,
                    baseRevision: patch.baseRevision,
                    resultingRevision: notes.revision,
                    createdAtMilliseconds: now,
                    source: .synthesis
                ))
            }
            current.synthesisState.synthesizedSegmentIDs.formUnion(batch.map(\.id))
            current.synthesisState.pendingSegmentIDs.subtract(batch.map(\.id))
            current.synthesisState.status = current.synthesisState.isPending ? .scheduled : .completed
            current.synthesisState.nextAttemptAtMilliseconds = current.synthesisState.isPending
                ? clock.nowMilliseconds()
                : nil
            current.synthesisState.lastErrorCode = nil
            publishDocument(current, asActive: activeDocument?.session.id == sessionID)
            try await store.save(current)
            return .succeeded
        } catch {
            await recordSynthesisFailure(.invalidResponse, sessionID: sessionID)
            return .failed
        }
    }

    private func recordSynthesisFailure(_ code: MeetingSynthesisErrorCode, sessionID: UUID) async {
        guard var current = documents[sessionID] else { return }
        let now = clock.nowMilliseconds()
        current.synthesisState.lastErrorCode = code
        if code.allowsAutomaticRetry {
            current.synthesisState.status = .retryScheduled
            current.synthesisState.nextAttemptAtMilliseconds = now + retryDelayMilliseconds(
                attemptCount: current.synthesisState.attemptCount
            )
        } else {
            current.synthesisState.status = .failed
            current.synthesisState.nextAttemptAtMilliseconds = nil
        }
        publishDocument(current, asActive: activeDocument?.session.id == sessionID)
        try? await store.save(current)
        appendIssue(.synthesis, message: synthesisMessage(code))
    }

    private func retryDelayMilliseconds(attemptCount: Int) -> Int64 {
        let delays: [Int64] = [30000, 60000, 120_000, 300_000]
        return delays[min(max(0, attemptCount - 1), delays.count - 1)]
    }

    private func synthesisMessage(_ code: MeetingSynthesisErrorCode) -> String {
        switch code {
        case .invalidRequest:
            "Notes generation stopped because the app and runtime request contracts do not match."
        case .modelUnavailable:
            "Notes generation stopped because the selected model is unavailable."
        case .credentialUnavailable:
            "Notes generation stopped because the selected model requires authentication."
        case .providerTimeout:
            "Notes generation timed out and will retry automatically."
        case .providerFailure:
            "The notes provider failed and will retry automatically."
        case .invalidResponse:
            "The notes provider returned an invalid response and will retry automatically."
        case .cancelled:
            "Notes generation was interrupted and will retry automatically."
        }
    }

    private func cancelSynthesisTask(sessionID: UUID) async {
        guard let task = synthesisTasks.removeValue(forKey: sessionID) else { return }
        task.cancel()
        await task.value
    }

    private func cancelPeriodicSynthesis() async {
        guard let sessionID = activeDocument?.session.id else { return }
        await cancelSynthesisTask(sessionID: sessionID)
    }

    private func finishActiveSession(interrupted: Bool) async {
        elapsedTask?.cancel()
        elapsedTask = nil
        await cancelPeriodicSynthesis()
        var wasInterrupted = interrupted
        if let runtime {
            if runtime.capture.isCapturing {
                do {
                    try await runtime.capture.stop()
                } catch {
                    wasInterrupted = true
                    appendIssue(.capture, message: "Audio capture did not stop cleanly.")
                }
            }
            await runtime.ingress.finish()
            let drainResult = await runtime.pipeline.waitUntilFinished(timeout: .seconds(30))
            if drainResult != .finished {
                await runtime.pipeline.cancel()
                wasInterrupted = true
                appendIssue(.transcription, message: "Local transcription did not finish before the shutdown deadline.")
            }
        }
        if let sessionID = activeDocument?.session.id {
            _ = await synthesizeBatch(sessionID: sessionID, generation: lifecycleGeneration)
        }
        guard var document = activeDocument else {
            runtime = nil
            lifecycleGeneration = nil
            status = .idle
            return
        }
        let sessionID = document.session.id
        let now = max(clock.nowMilliseconds(), document.session.updatedAtMilliseconds)
        do {
            if document.session.lifecycle.phase.isActive {
                if wasInterrupted {
                    try document.session.transition(
                        to: .interrupted,
                        atMilliseconds: now,
                        interruptionReason: interruptionReason ?? "Recording ended unexpectedly."
                    )
                } else {
                    try document.session.transition(to: .completed, atMilliseconds: now)
                }
            }
            publishDocument(document, asActive: true)
            let finalized: MeetingSessionDocument
            if settingsStore.allowingDestructiveRetention {
                let result = try await store.finalizeAndEnforceRetention(
                    document,
                    settings: document.configuration.persistenceSettings,
                    nowMilliseconds: now
                )
                finalized = result.document
            } else {
                finalized = try await store.finalize(document, settings: document.configuration.persistenceSettings)
            }
            var current = documents[sessionID] ?? document
            current.audioChunks = finalized.audioChunks
            publishDocument(current, asActive: false)
            activeDocument = nil
            try await store.save(current)
            refreshSessions()
            status = .completed
            if current.synthesisState.isPending,
               current.synthesisState.lastErrorCode?.allowsAutomaticRetry != false
            {
                await scheduleSynthesisIfNeeded(sessionID: sessionID, generation: nil)
            }
        } catch {
            if let current = documents[sessionID] {
                activeDocument = current
            }
            appendIssue(.persistence, message: "The meeting could not be finalized.")
            status = .failed("The meeting could not be finalized.")
        }
        runtime = nil
        partialTranscriptSegments.removeAll(keepingCapacity: true)
        lifecycleGeneration = nil
        interruptionReason = nil
        elapsedDuration = 0
    }

    private func drainRuntime() async {
        guard let runtime else { return }
        if runtime.capture.isCapturing {
            try? await runtime.capture.stop()
        }
        await runtime.ingress.finish()
        let result = await runtime.pipeline.waitUntilFinished(timeout: .seconds(30))
        if result != .finished {
            await runtime.pipeline.cancel()
        }
        self.runtime = nil
    }

    private func saveUpdatedDocument(_ document: MeetingSessionDocument) async {
        publishDocument(document, asActive: activeDocument?.session.id == document.session.id)
        do {
            try await store.save(document)
        } catch {
            appendIssue(.persistence, message: "The meeting update could not be saved.")
            status = .failed("The meeting update could not be saved.")
        }
    }

    private func publishDocument(_ document: MeetingSessionDocument, asActive: Bool) {
        documents[document.session.id] = document
        if asActive {
            activeDocument = document
        }
        if selectedDocument == nil || selectedDocument?.session.id == document.session.id {
            selectedDocument = document
        }
        refreshSessions()
    }

    private func refreshSessions() {
        sessions = documents.values.map(\.session).sorted {
            if $0.updatedAtMilliseconds == $1.updatedAtMilliseconds {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.updatedAtMilliseconds > $1.updatedAtMilliseconds
        }
    }

    private func startElapsedUpdates(startedAtMilliseconds: Int64) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                elapsedDuration = TimeInterval(max(0, clock.nowMilliseconds() - startedAtMilliseconds)) / 1000
                try? await clock.sleep(forMilliseconds: 1000)
            }
        }
    }

    private func consume(_ consent: MeetingRecordingConsent) -> Bool {
        guard let issued = issuedConsents.removeValue(forKey: consent.id),
              issued == consent.configuration,
              consentIsCurrent(consent.configuration)
        else {
            return false
        }
        return true
    }

    private func consentIsCurrent(_ configuration: MeetingSessionConfiguration) -> Bool {
        let now = clock.nowMilliseconds()
        guard configuration.hasCurrentDisclosure,
              now >= configuration.consentedAtMilliseconds,
              now <= configuration.consentExpiresAtMilliseconds,
              settingsStore.settings.sessionConfiguration(
                  consentedAtMilliseconds: configuration.consentedAtMilliseconds
              ) == configuration,
              (try? MeetingTranscriptionPrivacyPolicy.validate(configuration)) != nil
        else {
            return false
        }
        return true
    }

    private func startupIsCurrent(_ generation: UUID) -> Bool {
        startupGeneration == generation && lifecycleGeneration == generation && !Task.isCancelled
    }

    private func finishCancelledStart(generation: UUID) {
        guard lifecycleGeneration == generation, activeDocument == nil else { return }
        lifecycleGeneration = nil
        if status != .stopping {
            status = .idle
        }
    }

    private func appendIssue(_ kind: MeetingNotesCoordinatorIssue.Kind, message: String) {
        issues.append(MeetingNotesCoordinatorIssue(
            id: UUID(),
            kind: kind,
            occurredAtMilliseconds: clock.nowMilliseconds(),
            message: message
        ))
        if issues.count > 100 {
            issues.removeFirst(issues.count - 100)
        }
    }

    private func normalizedTitle(_ title: String) -> String {
        let normalized = title.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Meeting" : String(normalized.prefix(200))
    }

    private func updateTrackHealth(
        _ update: MeetingTranscriptionTrackHealthRecord,
        document: inout MeetingSessionDocument
    ) {
        let sanitizedCode = update.code.flatMap {
            try? MeetingTranscriptionValidation.normalizedIdentifier($0, field: "trackHealth.code")
        }
        transcriptionTrackHealth[update.trackID] = MeetingTranscriptionTrackHealth(
            providerEpoch: update.providerEpoch,
            state: update.state,
            updatedAtMilliseconds: update.updatedAtMilliseconds,
            code: sanitizedCode
        )
        document.transcriptionTrackHealth.removeAll { $0.trackID == update.trackID }
        document.transcriptionTrackHealth.append(MeetingTranscriptionTrackHealthRecord(
            trackID: update.trackID,
            providerEpoch: update.providerEpoch,
            state: update.state,
            updatedAtMilliseconds: update.updatedAtMilliseconds,
            code: sanitizedCode
        ))
    }

    private func runtimeState(_ state: MeetingTranscriptionSessionState) -> MeetingTranscriptionTrackRuntimeState {
        switch state {
        case .starting: .starting
        case .ready: .ready
        case .draining: .draining
        case .completed: .completed
        case .cancelled: .cancelled
        }
    }

    private func sanitizedWarning(code: String) -> String {
        if code.lowercased().contains("rotation") {
            return "Transcription session is rotating."
        }
        return "Transcription provider reported a recoverable warning."
    }
}
