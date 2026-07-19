import Foundation

struct MeetingDocumentLimits {
    var maximumTracks = 16
    var maximumAudioChunks = 100_000
    var maximumTranscriptSegments = 100_000
    var maximumCommittedTranscriptMetadata = 100_000
    var maximumRecordingGaps = 100_000
    var maximumTranscriptionGaps = 100_000
    var maximumTranscriptionTrackHealth = 16
    var maximumRevisions = 10000
    var maximumTranscriptTextLength = 20000
}

struct MeetingDocumentValidator {
    let limits: MeetingDocumentLimits

    init(limits: MeetingDocumentLimits = MeetingDocumentLimits()) {
        self.limits = limits
    }

    func validate(_ document: MeetingSessionDocument) throws {
        guard document.version == MeetingSessionDocument.currentVersion,
              document.notes.sessionID == document.session.id,
              document.tracks.count <= limits.maximumTracks,
              document.audioChunks.count <= limits.maximumAudioChunks,
              document.transcriptSegments.count <= limits.maximumTranscriptSegments,
              document.committedTranscriptMetadata.count <= limits.maximumCommittedTranscriptMetadata,
              document.recordingGaps.count <= limits.maximumRecordingGaps,
              document.transcriptionGaps.count <= limits.maximumTranscriptionGaps,
              document.transcriptionTrackHealth.count <= limits.maximumTranscriptionTrackHealth,
              document.noteRevisions.count <= limits.maximumRevisions
        else {
            throw MeetingDomainError.invalidDocument
        }
        try document.session.validate()
        guard (1 ... 30).contains(document.configuration.synthesisIntervalMinutes),
              (1 ... 3650).contains(document.configuration.retentionDays),
              document.configuration.version == MeetingSessionConfiguration.currentVersion,
              document.configuration.notesProviderID.count <= 64,
              document.configuration.notesModelID.count <= 192,
              document.configuration.styleInstructions.count <= 2000,
              document.configuration.sttKeyterms.count <= 100,
              document.configuration.sttMaximumSpeakers.map({ 1 ... 32 ~= $0 }) ?? true,
              document.configuration.rawAudioRecipient.count <= 128,
              document.configuration.rawAudioRegionID == document.configuration.transcriptionRoute.regionID,
              document.configuration.rawAudioRetention == document.configuration.transcriptionRoute.retention,
              document.configuration.sttAccountAttestations.count <= MeetingTranscriptionAccountAttestationKind.allCases.count,
              document.configuration.sttAccountAttestations.allSatisfy(\.isExact),
              Set(document.configuration.sttAccountAttestations.map(\.kind)).count ==
              document.configuration.sttAccountAttestations.count,
              document.configuration.disclosureClaims.count <= 16,
              document.configuration.disclosureClaims.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1000 }),
              document.configuration.disclosureVersion >= 0,
              document.configuration.consentedAtMilliseconds >= 0,
              document.configuration.consentExpiresAtMilliseconds >= document.configuration.consentedAtMilliseconds,
              document.synthesisState.synthesizedSegmentIDs.isSubset(of: Set(document.transcriptSegments.map(\.id))),
              document.synthesisState.pendingSegmentIDs.isSubset(of: Set(document.transcriptSegments.map(\.id))),
              document.synthesisState.attemptCount >= 0,
              document.synthesisState.lastAttemptAtMilliseconds.map({ $0 >= 0 }) ?? true,
              document.synthesisState.nextAttemptAtMilliseconds.map({ $0 >= 0 }) ?? true,
              validSynthesisLifecycle(document.synthesisState)
        else {
            throw MeetingDomainError.invalidDocument
        }
        if document.configuration.transcriptionRoute.mode != .localChunked,
           document.configuration.hasCurrentDisclosure
        {
            guard let endpoint = document.configuration.transcriptionEndpoint,
                  let model = document.configuration.transcriptionModel,
                  endpoint.providerID == document.configuration.transcriptionRoute.providerID,
                  endpoint.regionID == document.configuration.transcriptionRoute.regionID,
                  model.id == document.configuration.transcriptionRoute.modelID,
                  model.modes.contains(document.configuration.transcriptionRoute.mode)
            else {
                throw MeetingDomainError.invalidDocument
            }
            try endpoint.validate()
        }
        try validateUniqueIDs(document.tracks.map(\.id))
        try validateUniqueIDs(document.audioChunks.map(\.id))
        try validateUniqueIDs(document.transcriptSegments.map(\.id))
        try validateUniqueIDs(document.committedTranscriptMetadata.map(\.id))
        try validateUniqueIDs(document.recordingGaps.map(\.id))
        try validateUniqueIDs(document.transcriptionGaps.map(\.id))
        try validateUniqueIDs(document.transcriptionTrackHealth.map(\.id))
        try validateUniqueIDs(document.noteRevisions.map(\.id))
        let tracks = Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, $0) })
        for track in document.tracks {
            try validate(track)
        }
        for chunk in document.audioChunks {
            try validate(chunk, tracks: tracks)
        }
        for segment in document.transcriptSegments {
            try validate(segment, tracks: tracks)
        }
        for gap in document.recordingGaps {
            guard tracks[gap.trackID] != nil,
                  gap.firstSequenceNumber >= 0,
                  gap.lastSequenceNumber >= gap.firstSequenceNumber,
                  gap.droppedBufferCount > 0,
                  gap.droppedFrameCount > 0,
                  gap.startMilliseconds >= 0,
                  gap.endMilliseconds > gap.startMilliseconds,
                  !gap.reason.isEmpty,
                  gap.reason.count <= 120
            else {
                throw MeetingDomainError.invalidDocument
            }
        }
        let finalSegmentIDs = Set(document.transcriptSegments.filter(\.isFinal).map(\.id))
        guard document.committedTranscriptMetadata.allSatisfy({ metadata in
            finalSegmentIDs.contains(metadata.id) &&
                tracks[metadata.trackID] != nil &&
                metadata.providerID.count <= 128 &&
                metadata.modelID.count <= 128 &&
                metadata.regionID.count <= 128 &&
                metadata.words.count <= 10000
        })
        else {
            throw MeetingDomainError.invalidDocument
        }
        for gap in document.transcriptionGaps {
            guard let track = tracks[gap.trackID],
                  gap.sampleRange.sampleRateHertz == track.sampleRateHertz,
                  gap.startMilliseconds >= track.startedAtMilliseconds,
                  gap.endMilliseconds > gap.startMilliseconds,
                  !gap.code.isEmpty,
                  gap.code.count <= 128
            else {
                throw MeetingDomainError.invalidDocument
            }
        }
        for health in document.transcriptionTrackHealth {
            guard tracks[health.trackID] != nil,
                  health.updatedAtMilliseconds >= document.session.lifecycle.createdAtMilliseconds,
                  health.code.map({ !$0.isEmpty && $0.count <= 128 }) ?? true
            else {
                throw MeetingDomainError.invalidDocument
            }
        }
        let allowedProjects = Set(document.session.projectIDs)
        try MeetingNotesReducer().validateSnapshot(
            document.notes,
            transcriptSegments: document.transcriptSegments,
            allowedProjectIDs: allowedProjects
        )
        guard document.noteRevisions.allSatisfy({
            $0.baseRevision >= 0 &&
                $0.resultingRevision == $0.baseRevision + 1 &&
                $0.resultingRevision <= document.notes.revision &&
                $0.createdAtMilliseconds >= document.session.lifecycle.createdAtMilliseconds
        })
        else {
            throw MeetingDomainError.invalidDocument
        }
    }

    private func validSynthesisLifecycle(_ state: MeetingSynthesisState) -> Bool {
        if state.isPending {
            return state.status != .idle && state.status != .completed
        }
        return state.status == .idle || state.status == .completed
    }

    private func validate(_ track: MeetingSourceTrack) throws {
        guard !track.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              track.displayName.count <= 120,
              track.sampleRateHertz >= 8000,
              track.sampleRateHertz <= 384_000,
              (1 ... 32).contains(track.channelCount),
              track.startedAtMilliseconds >= 0
        else {
            throw MeetingDomainError.invalidTrack
        }
    }

    private func validate(_ chunk: MeetingAudioChunkMetadata, tracks: [UUID: MeetingSourceTrack]) throws {
        guard let track = tracks[chunk.trackID],
              chunk.sampleRange.sampleRateHertz == track.sampleRateHertz,
              chunk.sampleRange.startFrame >= 0,
              chunk.sampleRange.endFrame > chunk.sampleRange.startFrame,
              chunk.capturedAtMilliseconds >= track.startedAtMilliseconds,
              chunk.byteCount >= 0
        else {
            throw MeetingDomainError.invalidAudioChunk
        }
    }

    private func validate(_ segment: MeetingTranscriptSegment, tracks: [UUID: MeetingSourceTrack]) throws {
        guard let track = tracks[segment.trackID],
              segment.sampleRange.sampleRateHertz == track.sampleRateHertz,
              segment.sampleRange.startFrame >= 0,
              segment.sampleRange.endFrame > segment.sampleRange.startFrame,
              segment.startMilliseconds >= 0,
              segment.endMilliseconds > segment.startMilliseconds,
              segment.createdAtMilliseconds >= segment.startMilliseconds,
              !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              segment.text.count <= limits.maximumTranscriptTextLength,
              (segment.speakerLabel?.count ?? 0) <= 120
        else {
            throw MeetingDomainError.invalidTranscriptSegment
        }
    }

    private func validateUniqueIDs(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw MeetingDomainError.invalidDocument }
    }
}
