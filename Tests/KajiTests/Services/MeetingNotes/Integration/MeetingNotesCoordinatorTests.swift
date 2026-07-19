import Foundation
import Testing

@testable import Kaji

@MainActor
@Suite("Meeting notes coordinator")
struct MeetingNotesCoordinatorTests {
    @Test("start and stop drain capture, ingress, and pipeline in order")
    func startStopOrderAndIdempotency() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()

        await harness.start()
        #expect(harness.coordinator.status == .recording)
        await harness.coordinator.stop()
        await harness.coordinator.stop()

        #expect(await harness.recorder.values == [
            "pipeline.start", "capture.start", "capture.stop", "ingress.finish", "pipeline.wait",
        ])
        #expect(harness.coordinator.sessions.first?.lifecycle.phase == .completed)
    }

    @Test("picker cancellation creates no session")
    func pickerCancellation() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        harness.picker.result = .failure(MeetingContentPickerError.cancelled)
        await harness.coordinator.prepare()

        await harness.start()

        #expect(harness.coordinator.status == .idle)
        #expect(harness.coordinator.sessions.isEmpty)
        #expect(harness.factory.makeCount == 0)
    }

    @Test("capture start failure drains and persists an interrupted session")
    func captureFailure() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        harness.factory.capture.startError = MeetingAudioError.streamSetupFailed("test")
        await harness.coordinator.prepare()

        await harness.start()

        #expect(await harness.recorder.values == [
            "pipeline.start", "capture.start", "ingress.finish", "pipeline.wait",
        ])
        #expect(harness.coordinator.sessions.first?.lifecycle.phase == .interrupted)
        #expect(harness.coordinator.activeDocument == nil)
    }

    @Test("transcripts are sorted and exact overlapping repeats are deduplicated")
    func transcriptSortingAndDeduplication() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        let later = try segment(source: source, startFrame: 16_000, text: "Second")
        let first = try segment(source: source, startFrame: 0, text: "First")
        let duplicate = MeetingTranscriptSegment(
            id: UUID(),
            trackID: first.trackID,
            sampleRange: first.sampleRange,
            startMilliseconds: first.startMilliseconds,
            endMilliseconds: first.endMilliseconds,
            text: "  FIRST ",
            speakerLabel: nil,
            isFinal: true,
            createdAtMilliseconds: first.createdAtMilliseconds
        )

        await harness.factory.emit(.transcript(later))
        await harness.factory.emit(.transcript(first))
        await harness.factory.emit(.transcript(duplicate))

        #expect(harness.coordinator.activeDocument?.transcriptSegments.map(\.text) == ["First", "Second"])
        await harness.coordinator.stop()
    }

    @Test("final synthesis coalesces finalized progress into one request")
    func synthesisCoalescing() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "One")))
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 16_000, text: "Two")))

        await harness.coordinator.stop()

        #expect(harness.synthesizer.requests.count == 1)
        #expect(harness.synthesizer.requests[0].transcriptSegments.map(\.text) == ["One", "Two"])
    }

    @Test("speaker amendments requeue synthesized notes with source metadata")
    func speakerAmendmentRequeuesNotes() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.clock.controlsLongSleeps = true
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        let transcript = try segment(source: source, startFrame: 0, text: "Taylor owns the rollout")
        await harness.factory.emit(.transcript(transcript))
        await waitUntil { harness.clock.longSleepCount == 1 }
        harness.clock.resumeLongSleeps()
        await waitUntil {
            harness.synthesizer.requests.count == 1 &&
                harness.coordinator.activeDocument?.synthesisState.isPending == false
        }
        let committed = MeetingCommittedTranscriptMetadata(
            id: transcript.id,
            operationID: nil,
            trackID: transcript.trackID,
            source: .microphone,
            providerID: "test-provider",
            modelID: "test-model",
            regionID: "local",
            mode: .localChunked,
            providerEpoch: .initial,
            confidence: nil,
            words: [],
            speaker: nil,
            language: nil,
            committedAtMilliseconds: transcript.createdAtMilliseconds
        )
        var amended = committed
        amended.speaker = try MeetingNormalizedSpeaker(id: "speaker-1", label: "Taylor")
        await harness.factory.emit(.committedMetadata(committed))
        await harness.factory.emit(.metadataAmendment(amended))

        #expect(harness.coordinator.activeDocument?.synthesisState.isPending == true)
        #expect(harness.coordinator.activeDocument?.synthesisState.synthesizedSegmentIDs.contains(transcript.id) == false)
        await waitUntil { harness.clock.longSleepCount == 1 }
        harness.clock.resumeLongSleeps()
        await waitUntil {
            harness.synthesizer.requests.count == 2 &&
                harness.coordinator.activeDocument?.synthesisState.isPending == false
        }
        await harness.coordinator.stop()

        let request = try #require(harness.synthesizer.requests.last)
        #expect(harness.synthesizer.requests.count == 2)
        #expect(request.transcriptSegments.first?.speakerLabel == "Taylor")
        #expect(request.sourceKindsByTrackID[transcript.trackID] == .microphone)
        #expect(request.sourceLabelsByTrackID[transcript.trackID] == source.displayName)
    }

    @Test("an unavailable notes model never stops transcription")
    func noModelTranscriptionContinuity() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)

        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Still recording")))

        #expect(harness.coordinator.status == .recording)
        #expect(harness.coordinator.activeDocument?.transcriptSegments.count == 1)
        #expect(harness.coordinator.activeDocument?.synthesisState.isPending == false)
        #expect(harness.factory.capture.isCapturing)
        await harness.coordinator.stop()
        let sessionID = try #require(harness.coordinator.selectedDocument?.session.id)
        #expect(!harness.coordinator.hasPendingSynthesis(sessionID: sessionID))
    }

    @Test("startup recovery loads repaired sessions and applies retention")
    func recovery() async throws {
        let recoveredID = UUID()
        let store = MockMeetingSessionStore()
        await store.setDocuments([try MeetingNotesTestFixtures.document(id: recoveredID, phase: .interrupted)])
        await store.setRecoveredIDs([recoveredID])
        let harness = try CoordinatorHarness(store: store, modelConfigured: false)

        await harness.coordinator.prepare()

        #expect(harness.coordinator.sessions.map(\.id) == [recoveredID])
        #expect(harness.coordinator.issues.contains { $0.kind == .recovery })
        #expect(await store.retentionCallCount == 1)
    }

    @Test("stop waits for a suspended capture start and stops a stream that starts late")
    func stopDuringSuspendedCaptureStart() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        harness.factory.capture.suspendsStart = true
        await harness.coordinator.prepare()

        let startTask = Task { await harness.start() }
        await waitUntil { harness.factory.capture.startEntered }
        let stopTask = Task { await harness.coordinator.stop() }
        await waitUntil { harness.coordinator.status == .stopping }

        harness.factory.capture.resumeStart()
        await startTask.value
        await stopTask.value

        #expect(await harness.recorder.values == [
            "pipeline.start", "capture.start", "capture.stop", "ingress.finish", "pipeline.wait",
        ])
        #expect(!harness.factory.capture.isCapturing)
        #expect(harness.coordinator.activeDocument == nil)
        #expect(harness.coordinator.sessions.first?.lifecycle.phase == .completed)
    }

    @Test("stop cancels and awaits a suspended application picker")
    func stopDuringPicker() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        harness.picker.suspendsSelection = true
        await harness.coordinator.prepare()

        let startTask = Task { await harness.start() }
        await waitUntil { harness.picker.isActive }
        await harness.coordinator.stop()
        await startTask.value

        #expect(harness.coordinator.sessions.isEmpty)
        #expect(harness.factory.makeCount == 0)
        #expect(harness.coordinator.status == .idle)
    }

    @Test("stop performs one final synthesis attempt and leaves stale work retryable")
    func staleSynthesisReentrancy() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.synthesizer.suspendsResponses = true
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "One")))

        let stopTask = Task { await harness.coordinator.stop() }
        await waitUntil { harness.synthesizer.pendingCount == 1 }
        let decisionID = UUID()
        await harness.coordinator.updateUserNote(MeetingNotesPatch(
            sessionID: try #require(harness.coordinator.activeDocument?.session.id),
            baseRevision: 0,
            operations: [.upsertDecision(MeetingDecision(
                id: decisionID,
                text: "Keep the current implementation",
                evidence: [],
                isPinned: false
            ))]
        ))
        await harness.coordinator.pin(
            sessionID: try #require(harness.coordinator.activeDocument?.session.id),
            item: .decision(decisionID),
            isPinned: true
        )
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 16_000, text: "Two")))
        harness.synthesizer.resumeNext(operations: [.setSummary("stale")])
        await stopTask.value

        let document = try #require(harness.coordinator.selectedDocument)
        #expect(harness.synthesizer.requests.count == 1)
        #expect(document.notes.summary.isEmpty)
        #expect(document.notes.decisions.first?.isPinned == true)
        #expect(document.transcriptSegments.map(\.text) == ["One", "Two"])
        #expect(document.synthesisState.isPending)

        let retryTask = Task { await harness.coordinator.retrySynthesis(sessionID: document.session.id) }
        await waitUntil { harness.synthesizer.pendingCount == 1 && harness.synthesizer.requests.count == 2 }
        #expect(harness.synthesizer.requests[1].currentNotes.revision == 2)
        #expect(harness.synthesizer.requests[1].transcriptSegments.map(\.text) == ["One", "Two"])
        harness.synthesizer.resumeNext(operations: [])
        await retryTask.value
        #expect(!harness.coordinator.hasPendingSynthesis(sessionID: document.session.id))
    }

    @Test("late cancelled periodic response cannot overwrite final notes")
    func lateResponseAfterStop() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.synthesizer.suspendsResponses = true
        harness.clock.controlsLongSleeps = true
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "One")))
        await waitUntil { harness.clock.longSleepCount == 1 }
        harness.clock.resumeLongSleeps()
        await waitUntil { harness.synthesizer.pendingCount == 1 }

        let stopTask = Task { await harness.coordinator.stop() }
        await waitUntil { harness.coordinator.status == .stopping }
        harness.synthesizer.resumeNext(operations: [.setSummary("late response")])
        await waitUntil { harness.synthesizer.pendingCount == 1 && harness.synthesizer.requests.count == 2 }
        harness.synthesizer.resumeNext(operations: [])
        await stopTask.value

        #expect(harness.coordinator.selectedDocument?.notes.summary == "")
        #expect(harness.coordinator.selectedDocument?.session.lifecycle.phase == .completed)
    }

    @Test("failed final synthesis remains pending and can retry after completion")
    func retryFinalSynthesisFailure() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.synthesizer.nextError = KajiMeetingNotesAgentError.failed
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Retry me")))

        await harness.coordinator.stop()
        let sessionID = try #require(harness.coordinator.selectedDocument?.session.id)
        #expect(harness.coordinator.hasPendingSynthesis(sessionID: sessionID))
        #expect(harness.coordinator.selectedDocument?.session.lifecycle.phase == .completed)
        #expect(await harness.store.document(id: sessionID)?.synthesisState.isPending == true)

        await harness.coordinator.retrySynthesis(sessionID: sessionID)

        #expect(harness.synthesizer.requests.count == 2)
        #expect(!harness.coordinator.hasPendingSynthesis(sessionID: sessionID))
        #expect(harness.coordinator.selectedDocument?.synthesisState.synthesizedSegmentIDs.count == 1)
    }

    @Test("transient synthesis failure persists exponential retry and recovers")
    func transientSynthesisRetry() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.clock.controlsLongSleeps = true
        harness.synthesizer.nextError = KajiMeetingNotesAgentError.timedOut
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Retry automatically")))

        await harness.coordinator.stop()

        let failed = try #require(harness.coordinator.selectedDocument)
        #expect(failed.synthesisState.status == .retryScheduled)
        #expect(failed.synthesisState.attemptCount == 1)
        #expect(failed.synthesisState.lastErrorCode == .providerTimeout)
        #expect(failed.synthesisState.nextAttemptAtMilliseconds != nil)
        await waitUntil { harness.clock.longSleepCount == 1 }
        harness.clock.resumeLongSleeps()
        await waitUntil { harness.coordinator.selectedDocument?.synthesisState.status == .completed }

        #expect(harness.synthesizer.requests.count == 2)
        #expect(harness.coordinator.selectedDocument?.synthesisState.attemptCount == 2)
        #expect(harness.coordinator.selectedDocument?.synthesisState.lastErrorCode == nil)
    }

    @Test("contract synthesis failure pauses automatic retry until manual retry")
    func nonRetryableSynthesisFailure() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        harness.clock.controlsLongSleeps = true
        harness.synthesizer.nextError = KajiMeetingNotesAgentError.invalidRequest
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Retry manually")))

        await harness.coordinator.stop()

        let sessionID = try #require(harness.coordinator.selectedDocument?.session.id)
        #expect(harness.coordinator.selectedDocument?.synthesisState.status == .failed)
        #expect(harness.coordinator.selectedDocument?.synthesisState.lastErrorCode == .invalidRequest)
        #expect(harness.clock.longSleepCount == 0)

        await harness.coordinator.retrySynthesis(sessionID: sessionID)

        #expect(harness.coordinator.selectedDocument?.synthesisState.status == .completed)
        #expect(harness.coordinator.selectedDocument?.synthesisState.lastErrorCode == nil)
    }

    @Test("startup schedules pending terminal synthesis recovery")
    func startupSynthesisRecovery() async throws {
        let store = MockMeetingSessionStore()
        let harness = try CoordinatorHarness(store: store, modelConfigured: true)
        harness.clock.controlsLongSleeps = true
        let segment = try MeetingNotesTestFixtures.segment()
        let configuration = harness.settings.settings.sessionConfiguration(consentedAtMilliseconds: 1_000)
        let document = MeetingSessionDocument(
            session: try MeetingNotesTestFixtures.session(phase: .completed),
            tracks: [MeetingNotesTestFixtures.track()],
            transcriptSegments: [segment],
            configuration: configuration,
            synthesisState: MeetingSynthesisState(
                synthesizedSegmentIDs: [],
                pendingSegmentIDs: [segment.id],
                status: .retryScheduled,
                attemptCount: 1,
                lastAttemptAtMilliseconds: 2_001,
                nextAttemptAtMilliseconds: nil,
                lastErrorCode: .providerFailure
            )
        )
        await store.setDocuments([document])

        await harness.coordinator.prepare()
        await waitUntil { harness.clock.longSleepCount == 1 }
        harness.clock.resumeLongSleeps()
        await waitUntil { harness.coordinator.selectedDocument?.synthesisState.status == .completed }

        #expect(harness.synthesizer.requests.count == 1)
        #expect(harness.coordinator.selectedDocument?.synthesisState.attemptCount == 2)
        #expect(!harness.coordinator.hasPendingSynthesis(sessionID: document.session.id))
    }

    @Test("recording consent is required, single use, and bound to exact settings")
    func consentValidation() async throws {
        let absent = try CoordinatorHarness(modelConfigured: false)
        await absent.coordinator.prepare()
        await absent.coordinator.start()
        #expect(absent.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))
        #expect(absent.coordinator.sessions.isEmpty)

        let reused = try CoordinatorHarness(modelConfigured: false)
        await reused.coordinator.prepare()
        let consent = reused.coordinator.makeRecordingConsent()
        await reused.coordinator.start(consent: consent)
        await reused.coordinator.stop()
        await reused.coordinator.start(consent: consent)
        #expect(reused.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))
        #expect(reused.coordinator.sessions.count == 1)

        let mismatch = try CoordinatorHarness(modelConfigured: false)
        await mismatch.coordinator.prepare()
        let staleConsent = mismatch.coordinator.makeRecordingConsent()
        mismatch.settings.update { $0.includeMicrophone.toggle() }
        await mismatch.coordinator.start(consent: staleConsent)
        #expect(mismatch.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))
        #expect(mismatch.coordinator.sessions.isEmpty)
    }

    @Test("cloud consent expires and is invalidated by route changes")
    func cloudConsentExpiryAndMismatch() async throws {
        let stale = try CoordinatorHarness(modelConfigured: false)
        await stale.coordinator.prepare()
        stale.settings.update {
            $0.sttProviderID = "cloud-test"
            $0.sttModelID = "realtime"
            $0.sttMode = .cloudRealtime
            $0.sttRegionID = "us"
            $0.sttRetention = .providerDefault
            $0.sttCredentialProfileID = UUID()
        }
        let expired = stale.coordinator.makeRecordingConsent()
        stale.clock.advance(by: MeetingSessionConfiguration.consentValidityMilliseconds + 1)
        await stale.coordinator.start(consent: expired)
        #expect(stale.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))

        let mismatch = try CoordinatorHarness(modelConfigured: false)
        await mismatch.coordinator.prepare()
        mismatch.settings.update {
            $0.sttProviderID = "cloud-test"
            $0.sttModelID = "realtime"
            $0.sttMode = .cloudRealtime
            $0.sttRegionID = "us"
            $0.sttRetention = .providerDefault
            $0.sttCredentialProfileID = UUID()
        }
        let consent = mismatch.coordinator.makeRecordingConsent()
        mismatch.settings.update { $0.sttRegionID = "eu" }
        await mismatch.coordinator.start(consent: consent)
        #expect(mismatch.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))
    }

    @Test("consent expiry while the application picker is pending prevents runtime creation")
    func consentExpiryDuringPicker() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        harness.picker.suspendsSelection = true
        let consent = harness.coordinator.makeRecordingConsent()
        let start = Task { @MainActor in
            await harness.coordinator.start(consent: consent)
        }
        while !harness.picker.isActive {
            await Task.yield()
        }
        harness.clock.advance(by: MeetingSessionConfiguration.consentValidityMilliseconds + 1)
        harness.picker.resumeSelection()
        await start.value

        #expect(harness.coordinator.status == .unavailable(MeetingNotesCoordinatorError.invalidConsent.localizedDescription))
        #expect(harness.factory.makeCount == 0)
        #expect(!harness.factory.capture.startEntered)
    }

    @Test("consent is checked again immediately before capture starts")
    func consentExpiryBeforeCapture() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        harness.factory.onMakeRuntime = {
            harness.clock.advance(by: MeetingSessionConfiguration.consentValidityMilliseconds + 1)
        }

        await harness.start()

        #expect(!harness.factory.capture.startEntered)
        #expect(harness.coordinator.selectedDocument?.session.lifecycle.phase == .interrupted)
    }

    @Test("partials remain in memory until a final is committed")
    func partialAndFinalState() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        let final = try segment(source: source, startFrame: 0, text: "Final")
        let partial = MeetingTranscriptSegment(
            id: final.id,
            trackID: final.trackID,
            sampleRange: final.sampleRange,
            startMilliseconds: final.startMilliseconds,
            endMilliseconds: final.endMilliseconds,
            text: "Draft",
            speakerLabel: nil,
            isFinal: false,
            createdAtMilliseconds: final.createdAtMilliseconds
        )

        await harness.factory.emit(.partialTranscript(partial))
        #expect(harness.coordinator.partialTranscriptSegments[partial.id]?.text == "Draft")
        #expect(harness.coordinator.activeDocument?.transcriptSegments.isEmpty == true)
        await harness.factory.emit(.transcript(final))
        #expect(harness.coordinator.partialTranscriptSegments[partial.id] == nil)
        #expect(harness.coordinator.activeDocument?.transcriptSegments.map(\.text) == ["Final"])
        await harness.coordinator.stop()
    }

    @Test("usage rate and track session events surface without transcript data")
    func transcriptionOperationalEvents() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        let context = try MeetingTranscriptionEventContext(
            eventID: UUID(),
            sessionID: try #require(harness.coordinator.activeDocument?.session.id),
            trackID: source.trackID,
            source: .microphone,
            providerEpoch: .initial,
            sequenceNumber: 0,
            emittedAtMilliseconds: source.startedAtMilliseconds
        )
        await harness.factory.emit(.transcriptionUsage(try MeetingTranscriptionUsageEvent(
            context: context,
            metrics: [MeetingTranscriptionUsageMetric(billingUnit: "seconds", quantity: 12)]
        )))
        await harness.factory.emit(.transcriptionRateLimit(try MeetingTranscriptionRateLimitEvent(
            context: context,
            scope: "requests",
            retryAfterMilliseconds: 500
        )))
        await harness.factory.emit(.transcriptionSession(try MeetingTranscriptionSessionEvent(
            context: context,
            state: .ready
        )))
        await harness.factory.emit(.transcriptionWarning(try MeetingTranscriptionWarningEvent(
            context: context,
            code: "provider-overloaded",
            message: "secret provider response body",
            isRecoverable: true
        )))
        await harness.factory.emit(.transcriptionTrackHealth(try MeetingTranscriptionTrackHealthEvent(
            trackID: source.trackID,
            providerEpoch: .initial,
            state: .reconnecting,
            updatedAtMilliseconds: source.startedAtMilliseconds + 1,
            code: "reconnecting"
        )))
        let range = try MeetingCanonicalSampleRange(startFrame: 0, endFrame: 16_000, sampleRateHertz: 16_000)
        await harness.factory.emit(.transcriptionFailureRange(try MeetingTranscriptionFailureEvent(
            context: context,
            code: "runtime-disconnected",
            message: "secret provider response body",
            classification: .unavailable
        ), range))

        #expect(harness.coordinator.transcriptionUsage["seconds"] == 12)
        #expect(harness.coordinator.transcriptionRateLimitWarning == "Transcription rate limited. Retry in 500 ms.")
        #expect(harness.coordinator.transcriptionWarnings.last == "Transcription provider reported a recoverable warning.")
        #expect(harness.coordinator.transcriptionTrackHealth[source.trackID]?.state == .reconnecting)
        #expect(harness.coordinator.activeDocument?.transcriptionTrackHealth.first?.state == .reconnecting)
        #expect(harness.coordinator.activeDocument?.transcriptionGaps.first?.code == "runtime-disconnected")
        await harness.coordinator.stop()
        let sessionID = try #require(harness.coordinator.selectedDocument?.session.id)
        #expect(await harness.store.document(id: sessionID)?.transcriptionTrackHealth.first?.state == .reconnecting)
        #expect(await harness.store.document(id: sessionID)?.transcriptionGaps.first?.code == "runtime-disconnected")
    }

    @Test("session synthesis uses frozen disclosed settings")
    func frozenSessionSettings() async throws {
        let harness = try CoordinatorHarness(modelConfigured: true)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        harness.settings.update {
            $0.notesProviderID = "changed"
            $0.notesModelID = "changed-model"
            $0.styleInstructions = "changed"
            $0.shareProjectContext = true
            $0.contextScope = .all
        }
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Frozen")))
        await harness.coordinator.stop()

        let request = try #require(harness.synthesizer.requests.first)
        #expect(request.providerID == "test")
        #expect(request.modelID == "notes")
        #expect(request.styleInstructions.isEmpty)
        #expect(request.projectContext == nil)
        let configuration = try #require(harness.coordinator.selectedDocument?.configuration)
        #expect(configuration.includeSystemAudio)
        #expect(configuration.includeMicrophone)
        #expect(configuration.disclosureVersion == MeetingSessionConfiguration.currentDisclosureVersion)
        #expect(configuration.consentedAtMilliseconds > 0)
    }

    @Test("history selection stays stable while active meeting receives updates")
    func stableHistorySelection() async throws {
        let historical = try MeetingNotesTestFixtures.document(phase: .completed)
        let store = MockMeetingSessionStore()
        await store.setDocuments([historical])
        let harness = try CoordinatorHarness(store: store, modelConfigured: false)
        await harness.coordinator.prepare()
        harness.coordinator.select(sessionID: historical.session.id)
        await harness.start(title: "Active")
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "Update")))

        #expect(harness.coordinator.selectedDocument?.session.id == historical.session.id)
        #expect(harness.coordinator.activeDocument?.session.id != historical.session.id)
        await harness.coordinator.stop()
        #expect(harness.coordinator.selectedDocument?.session.id == historical.session.id)
    }

    @Test("active edits target the displayed meeting while history selection remains stable")
    func explicitActiveEditTarget() async throws {
        let historical = try MeetingNotesTestFixtures.document(phase: .completed)
        let store = MockMeetingSessionStore()
        await store.setDocuments([historical])
        let harness = try CoordinatorHarness(store: store, modelConfigured: false)
        await harness.coordinator.prepare()
        harness.coordinator.select(sessionID: historical.session.id)
        await harness.start(title: "Active")
        let active = try #require(harness.coordinator.activeDocument)

        await harness.coordinator.updateUserNote(MeetingNotesPatch(
            sessionID: active.session.id,
            baseRevision: active.notes.revision,
            operations: [.setSummary("Active summary")]
        ))

        #expect(harness.coordinator.activeDocument?.notes.summary == "Active summary")
        #expect(harness.coordinator.selectedDocument?.session.id == historical.session.id)
        #expect(harness.coordinator.selectedDocument?.notes.summary == historical.notes.summary)
        await harness.coordinator.stop()
    }

    @Test("drain timeout cancels and awaits the pipeline before finalization")
    func drainTimeoutCancellationRace() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.factory.pipeline.setDrainResult(.timedOut)
        await harness.coordinator.prepare()
        await harness.start()

        await harness.coordinator.stop()

        #expect(await harness.recorder.values == [
            "pipeline.start", "capture.start", "capture.stop", "ingress.finish", "pipeline.wait", "pipeline.cancel",
        ])
        #expect(await harness.factory.pipeline.wasCancellationAwaited())
        #expect(harness.coordinator.sessions.first?.lifecycle.phase == .interrupted)
    }

    @Test("invalid transcript output is rejected before document mutation")
    func invalidTranscriptOutput() async throws {
        let harness = try CoordinatorHarness(modelConfigured: false)
        await harness.coordinator.prepare()
        await harness.start()
        let source = try #require(harness.factory.microphoneSource)
        await harness.factory.emit(.transcript(try segment(source: source, startFrame: 0, text: "   \n\t")))
        await harness.factory.emit(.transcript(try segment(
            source: source,
            startFrame: 16_000,
            text: String(repeating: "a", count: 20_001)
        )))

        #expect(harness.coordinator.activeDocument?.transcriptSegments.isEmpty == true)
        #expect(harness.coordinator.issues.filter { $0.kind == .transcription }.count == 2)
        await harness.coordinator.stop()
    }

    @Test("transcript timestamps are relative to capture start")
    func relativeTranscriptTimestamp() {
        #expect(MeetingNotesTimeFormatter.transcript(125_000, relativeTo: 120_000) == "00:05")
        #expect(MeetingNotesTimeFormatter.transcript(100, relativeTo: 200) == "00:00")
    }

    @Test("response cancellation before continuation installation completes immediately")
    func responseCancellationBeforeContinuation() async throws {
        let sessionID = UUID()
        let notes = MeetingNotesSnapshot.empty(sessionID: sessionID, title: "Meeting", createdAtMilliseconds: 1_000)
        let request = MeetingNotesSynthesisRequest(
            sessionID: sessionID,
            transcriptRevision: 1,
            transcriptSegments: [try MeetingNotesTestFixtures.segment()],
            currentNotes: notes,
            projectContext: nil
        )
        let response = KajiMeetingNotesResponseBox(
            process: KajiAgentProcess(),
            commandID: "command",
            request: request
        )
        var actionRan = false
        response.fail(KajiMeetingNotesAgentError.failed)

        do {
            _ = try await response.run { actionRan = true }
            Issue.record("Expected cancellation failure")
        } catch let error as KajiMeetingNotesAgentError {
            #expect(error == .failed)
        }

        #expect(!actionRan)
    }

    private func segment(
        source: MeetingAudioSourceIdentity,
        startFrame: Int64,
        text: String
    ) throws -> MeetingTranscriptSegment {
        let endFrame = startFrame + 16_000
        return MeetingTranscriptSegment(
            id: UUID(),
            trackID: source.trackID,
            sampleRange: try MeetingSampleRange(
                startFrame: startFrame,
                endFrame: endFrame,
                sampleRateHertz: 16_000
            ),
            startMilliseconds: source.startedAtMilliseconds + startFrame / 16,
            endMilliseconds: source.startedAtMilliseconds + endFrame / 16,
            text: text,
            speakerLabel: nil,
            isFinal: true,
            createdAtMilliseconds: source.startedAtMilliseconds + endFrame / 16
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0 ..< 10_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for controlled asynchronous state")
    }
}

@MainActor
private final class CoordinatorHarness {
    let recorder = MeetingOrderRecorder()
    let store: MockMeetingSessionStore
    let picker = MockMeetingPicker()
    let factory: MockMeetingRuntimeFactory
    let synthesizer = MockMeetingSynthesizer()
    let clock = MockMeetingClock()
    let coordinator: MeetingNotesCoordinator
    let settings: MeetingNotesSettingsStore

    init(store: MockMeetingSessionStore = MockMeetingSessionStore(), modelConfigured: Bool) throws {
        self.store = store
        factory = MockMeetingRuntimeFactory(recorder: recorder)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingCoordinatorSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = MeetingNotesSettingsStore(fileStore: .init(
            fileURL: directory.appendingPathComponent("settings.json"),
            options: .prettySorted
        ))
        if modelConfigured {
            settings.configureModel(providerID: "test", modelID: "notes")
        }
        coordinator = MeetingNotesCoordinator(
            store: store,
            settingsStore: settings,
            picker: picker,
            runtimeFactory: factory,
            transcriptionResolver: try MockMeetingTranscriptionResolver(),
            synthesizer: synthesizer,
            clock: clock,
            contextProvider: MockMeetingContextProvider()
        )
    }

    func start(title: String = "Meeting") async {
        let consent = coordinator.makeRecordingConsent()
        await coordinator.start(title: title, consent: consent)
    }
}

private actor MeetingOrderRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private actor MockMeetingSessionStore: MeetingSessionPersisting {
    private var documents: [MeetingSessionDocument] = []
    private var recoveredIDs: [UUID] = []
    private(set) var retentionCallCount = 0

    func setDocuments(_ documents: [MeetingSessionDocument]) {
        self.documents = documents
    }

    func setRecoveredIDs(_ ids: [UUID]) {
        recoveredIDs = ids
    }

    func document(id: UUID) -> MeetingSessionDocument? {
        documents.first { $0.session.id == id }
    }

    func save(_ document: MeetingSessionDocument) throws {
        documents.removeAll { $0.session.id == document.session.id }
        documents.append(document)
    }

    func load() throws -> MeetingLoadResult {
        MeetingLoadResult(documents: documents, issues: [])
    }

    func recoverStaleSessions(
        nowMilliseconds _: Int64,
        staleAfterMilliseconds _: Int64,
        reason _: String
    ) throws -> [UUID] {
        recoveredIDs
    }

    func deleteSession(id: UUID, includingPinned _: Bool) throws -> Bool {
        let previousCount = documents.count
        documents.removeAll { $0.session.id == id }
        return previousCount != documents.count
    }

    func finalize(
        _ document: MeetingSessionDocument,
        settings _: MeetingNotesSettings
    ) throws -> MeetingSessionDocument {
        try save(document)
        return document
    }

    func enforceRetention(
        settings _: MeetingNotesSettings,
        nowMilliseconds _: Int64
    ) throws -> MeetingRetentionResult {
        retentionCallCount += 1
        return MeetingRetentionResult(deletedSessionIDs: [], protectedSessionIDs: [], rawAudioDeletedSessionIDs: [])
    }
}

@MainActor
private final class MockMeetingPicker: MeetingContentPicking {
    var result: Result<MeetingContentSelection, Error> = .success(MeetingContentSelection())
    var suspendsSelection = false
    private(set) var isActive = false
    private var continuation: CheckedContinuation<MeetingContentSelection, Error>?

    func selectApplication() async throws -> MeetingContentSelection {
        isActive = true
        if suspendsSelection {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
        defer { isActive = false }
        return try result.get()
    }

    func cancel() {
        isActive = false
        continuation?.resume(throwing: MeetingContentPickerError.cancelled)
        continuation = nil
    }

    func resumeSelection() {
        isActive = false
        continuation?.resume(returning: MeetingContentSelection())
        continuation = nil
    }
}

@MainActor
private final class MockMeetingRuntimeFactory: MeetingRecordingRuntimeBuilding {
    let capture: MockMeetingCapture
    let pipeline: MockMeetingPipeline
    private let recorder: MeetingOrderRecorder
    private var eventHandler: MeetingAudioProcessingPipeline.EventHandler?
    private(set) var makeCount = 0
    private(set) var systemAudioSource: MeetingAudioSourceIdentity?
    private(set) var microphoneSource: MeetingAudioSourceIdentity?
    var onMakeRuntime: (() -> Void)?

    init(recorder: MeetingOrderRecorder) {
        self.recorder = recorder
        capture = MockMeetingCapture(recorder: recorder)
        pipeline = MockMeetingPipeline(recorder: recorder)
    }

    func makeRuntime(
        selection _: MeetingContentSelection,
        sessionID _: UUID,
        transcription _: MeetingResolvedTranscriptionProvider,
        sources: MeetingRecordingSources,
        eventHandler: @escaping MeetingAudioProcessingPipeline.EventHandler
    ) throws -> MeetingRecordingRuntime {
        onMakeRuntime?()
        makeCount += 1
        systemAudioSource = sources.systemAudio
        microphoneSource = sources.microphone
        self.eventHandler = eventHandler
        return MeetingRecordingRuntime(
            ingress: MockMeetingIngress(recorder: recorder),
            pipeline: pipeline,
            capture: capture
        )
    }

    func emit(_ event: MeetingAudioPipelineEvent) async {
        await eventHandler?(event)
    }
}

@MainActor
private final class MockMeetingCapture: MeetingAudioCaptureSession {
    private let recorder: MeetingOrderRecorder
    var startError: Error?
    var suspendsStart = false
    private(set) var startEntered = false
    private(set) var isCapturing = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(recorder: MeetingOrderRecorder) {
        self.recorder = recorder
    }

    func start() async throws {
        await recorder.append("capture.start")
        startEntered = true
        if suspendsStart {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
        if let startError { throw startError }
        isCapturing = true
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func stop() async throws {
        await recorder.append("capture.stop")
        isCapturing = false
    }
}

private actor MockMeetingIngress: MeetingAudioIngress {
    private let recorder: MeetingOrderRecorder

    init(recorder: MeetingOrderRecorder) {
        self.recorder = recorder
    }

    func finish() async {
        await recorder.append("ingress.finish")
    }

    func cancel() async {}
}

private actor MockMeetingPipeline: MeetingAudioPipelineSession {
    private let recorder: MeetingOrderRecorder
    private var drainResult = MeetingAudioPipelineDrainResult.finished
    private var cancellationAwaited = false

    init(recorder: MeetingOrderRecorder) {
        self.recorder = recorder
    }

    func start() async {
        await recorder.append("pipeline.start")
    }

    func waitUntilFinished() async {
        await recorder.append("pipeline.wait")
    }

    func waitUntilFinished(timeout _: Duration) async -> MeetingAudioPipelineDrainResult {
        await recorder.append("pipeline.wait")
        return drainResult
    }

    func cancel() async {
        await recorder.append("pipeline.cancel")
        await Task.yield()
        cancellationAwaited = true
    }

    func setDrainResult(_ result: MeetingAudioPipelineDrainResult) {
        drainResult = result
    }

    func wasCancellationAwaited() -> Bool {
        cancellationAwaited
    }
}

@MainActor
private final class MockMeetingTranscriptionResolver: MeetingTranscriptionProviderResolving {
    private let provider: FluidAudioMeetingTranscriptionProvider

    init() throws {
        provider = try FluidAudioMeetingTranscriptionProvider(
            models: [MeetingAudioTestFixtures.model],
            isModelCached: { _ in true }
        )
    }

    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider {
        MeetingResolvedTranscriptionProvider(
            provider: provider,
            route: try provider.route(modelID: MeetingAudioTestFixtures.model.id),
            keyterms: configuration.sttKeyterms,
            credentialProfileID: nil
        )
    }
}

@MainActor
private final class MockMeetingSynthesizer: MeetingNotesSynthesizing {
    private(set) var requests: [MeetingNotesSynthesisRequest] = []
    var suspendsResponses = false
    var nextError: Error?
    private var continuations: [CheckedContinuation<MeetingNotesPatch, Error>] = []

    var pendingCount: Int { continuations.count }

    func synthesizeNotes(for request: MeetingNotesSynthesisRequest) async throws -> MeetingNotesPatch {
        requests.append(request)
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        if suspendsResponses {
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return MeetingNotesPatch(
            sessionID: request.sessionID,
            baseRevision: request.currentNotes.revision,
            operations: []
        )
    }

    func resumeNext(operations: [MeetingNotesPatchOperation]) {
        guard !continuations.isEmpty else {
            Issue.record("No suspended synthesis response to resume")
            return
        }
        let continuation = continuations.removeFirst()
        let request = requests[requests.count - continuations.count - 1]
        continuation.resume(returning: MeetingNotesPatch(
            sessionID: request.sessionID,
            baseRevision: request.currentNotes.revision,
            operations: operations
        ))
    }
}

@MainActor
private final class MockMeetingClock: MeetingClock {
    private var now: Int64 = 1_000
    private var longSleepContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    var controlsLongSleeps = false

    var longSleepCount: Int { longSleepContinuations.count }

    func nowMilliseconds() -> Int64 {
        now += 1
        return now
    }

    func sleep(forMilliseconds milliseconds: Int64) async throws {
        if milliseconds >= 10_000 {
            if !controlsLongSleeps {
                try await Task.sleep(for: .milliseconds(milliseconds))
                return
            }
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    longSleepContinuations[id] = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelLongSleep(id: id)
                }
            }
            return
        }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
    func resumeLongSleeps() {
        let continuations = longSleepContinuations.values
        longSleepContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func cancelLongSleep(id: UUID) {
        longSleepContinuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    func advance(by milliseconds: Int64) {
        now += milliseconds
    }
}

@MainActor
private final class MockMeetingContextProvider: MeetingProjectContextProviding {
    func projectIDs(scope _: MeetingProjectContextScope) -> [UUID] {
        [MeetingNotesTestFixtures.projectID]
    }

    func context(
        scope _: MeetingProjectContextScope,
        allowedProjectIDs _: Set<UUID>
    ) -> MeetingProjectContext {
        MeetingProjectContext(projects: [], totalCharacterCount: 0)
    }
}
