import Foundation
import Testing
@testable import Kaji

@Suite("Meeting notes view state")
struct MeetingNotesViewStateTests {
    @Test("Coordinator statuses map to stable footer states")
    func footerStates() {
        #expect(MeetingNotesFooterVisualState.resolve(.idle) == .idle)
        #expect(MeetingNotesFooterVisualState.resolve(.completed) == .idle)
        #expect(MeetingNotesFooterVisualState.resolve(.recording) == .recording)
        #expect(MeetingNotesFooterVisualState.resolve(.starting) == .processing)
        #expect(MeetingNotesFooterVisualState.resolve(.synthesizing) == .processing)
        #expect(MeetingNotesFooterVisualState.resolve(.unavailable("Missing model")) == .error("Missing model"))
        #expect(MeetingNotesFooterVisualState.resolve(.failed("Capture failed")) == .error("Capture failed"))
    }

    @Test("Elapsed time is compact and does not become negative")
    func elapsedFormatting() {
        #expect(MeetingNotesTimeFormatter.elapsed(-2) == "00:00")
        #expect(MeetingNotesTimeFormatter.elapsed(65.9) == "01:05")
        #expect(MeetingNotesTimeFormatter.elapsed(3661) == "1:01:01")
        #expect(MeetingNotesTimeFormatter.transcript(125_000) == "02:05")
    }

    @Test("Status presentation distinguishes unavailable and processing")
    func statusPresentation() {
        #expect(MeetingNotesStatusPresentation.resolve(.idle) == nil)
        #expect(MeetingNotesStatusPresentation.resolve(.recording)?.kind == .active)
        #expect(MeetingNotesStatusPresentation.resolve(.synthesizing)?.kind == .neutral)
        #expect(MeetingNotesStatusPresentation.resolve(.unavailable("No source"))?.kind == .warning)
        #expect(MeetingNotesStatusPresentation.resolve(.failed("Failure"))?.kind == .error)
    }

    @Test("Synthesis lifecycle states remain distinct and actionable")
    func synthesisLifecyclePresentation() {
        let pendingID = UUID()
        let cases: [(MeetingSynthesisStatus, String, MeetingNotesSynthesisPresentation.Kind, Bool)] = [
            (.scheduled, "Notes scheduled", .neutral, true),
            (.generating, "Generating notes", .active, false),
            (.retryScheduled, "Notes retry scheduled", .warning, true),
            (.failed, "Notes generation failed", .error, true),
            (.completed, "Notes complete", .success, false),
        ]

        for (status, title, kind, canRetry) in cases {
            let state = MeetingSynthesisState(
                synthesizedSegmentIDs: status == .completed ? [pendingID] : [],
                pendingSegmentIDs: status == .completed ? [] : [pendingID],
                status: status,
                attemptCount: status == .completed ? 1 : 0,
                lastAttemptAtMilliseconds: nil,
                nextAttemptAtMilliseconds: nil,
                lastErrorCode: status == .failed ? .providerFailure : nil
            )
            let presentation = MeetingNotesSynthesisPresentation.resolve(state)

            #expect(presentation.title == title)
            #expect(presentation.kind == kind)
            #expect(presentation.canRetry == canRetry)
        }
    }

    @Test("Synthesis failures expose only stable safe reasons")
    func synthesisFailureReasons() {
        let expected: [(MeetingSynthesisErrorCode, String, Bool)] = [
            (.invalidRequest, "not supported", true),
            (.modelUnavailable, "model is unavailable", true),
            (.credentialUnavailable, "Authentication", true),
            (.providerTimeout, "timed out", false),
            (.providerFailure, "could not complete", false),
            (.invalidResponse, "could not safely apply", false),
            (.cancelled, "was cancelled", false),
        ]

        for (code, phrase, opensSettings) in expected {
            let state = MeetingSynthesisState(
                synthesizedSegmentIDs: [],
                pendingSegmentIDs: [UUID()],
                status: .failed,
                attemptCount: 1,
                lastAttemptAtMilliseconds: 1_000,
                nextAttemptAtMilliseconds: nil,
                lastErrorCode: code
            )
            let presentation = MeetingNotesSynthesisPresentation.resolve(state)

            #expect(presentation.detail.contains(phrase))
            #expect(presentation.shouldOpenSettings == opensSettings)
        }
    }

    @Test("Retry presentation includes persisted next attempt")
    func synthesisRetryDate() {
        let state = MeetingSynthesisState(
            synthesizedSegmentIDs: [],
            pendingSegmentIDs: [UUID()],
            status: .retryScheduled,
            attemptCount: 2,
            lastAttemptAtMilliseconds: 1_000,
            nextAttemptAtMilliseconds: 2_000,
            lastErrorCode: .providerTimeout
        )

        #expect(MeetingNotesSynthesisPresentation.resolve(state).detail.contains(MeetingNotesTimeFormatter.date(2_000)))
    }

    @Test("preflight disclosure separates raw audio and notes destinations")
    func preflightDisclosure() throws {
        var settings = MeetingNotesIntegrationSettings.defaults
        settings.sttProviderID = "cloud-stt"
        settings.sttModelID = "realtime-model"
        settings.sttMode = .cloudRealtime
        settings.sttRegionID = "eu"
        settings.sttRetention = .providerDefault
        settings.notesProviderID = "notes-provider"
        settings.notesModelID = "notes-model"
        settings.sttDiarizationEnabled = true
        let disclosure = MeetingRecordingDisclosure(settings: settings, readiness: .ready)

        #expect(disclosure.rawAudioLeavesMac)
        #expect(disclosure.transcriptionProviderID == "cloud-stt")
        #expect(disclosure.transcriptionModelID == "realtime-model")
        #expect(disclosure.regionID == "eu")
        #expect(disclosure.retention == .providerDefault)
        #expect(disclosure.sourceKinds == [.systemAudio, .microphone])
        #expect(disclosure.diarizationEnabled)
        #expect(disclosure.credentialReady)
        #expect(disclosure.notesDestination == "notes-provider/notes-model")
    }
}
