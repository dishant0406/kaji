import Foundation
import SwiftUI

enum MeetingNotesFooterVisualState: Equatable {
    case idle
    case recording
    case processing
    case error(String)

    static func resolve(_ status: MeetingNotesCoordinatorStatus) -> Self {
        switch status {
        case .recording:
            .recording
        case .preparing,
             .choosingApplication,
             .starting,
             .stopping,
             .synthesizing,
             .loading:
            .processing
        case let .unavailable(message),
             let .failed(message):
            .error(message)
        case .unconfigured:
            .error("Meeting notes are not configured.")
        case .idle,
             .completed:
            .idle
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle:
            "Idle"
        case .recording:
            "Recording"
        case .processing:
            "Processing"
        case let .error(message):
            "Error: \(message)"
        }
    }
}

enum MeetingNotesPanelTab: String, CaseIterable, Hashable {
    case notes = "Notes"
    case transcript = "Transcript"
    case history = "History"
}

struct MeetingRecordingDisclosure: Equatable {
    let rawAudioLeavesMac: Bool
    let transcriptionProviderID: String
    let transcriptionModelID: String
    let regionID: String
    let retention: MeetingTranscriptionDataRetentionClass
    let sourceKinds: [MeetingSourceKind]
    let diarizationEnabled: Bool
    let localFallbackEnabled: Bool
    let credentialReady: Bool
    let notesDestination: String?

    init(settings: MeetingNotesIntegrationSettings, readiness: MeetingTranscriptionReadiness) {
        rawAudioLeavesMac = settings.sttMode != .localChunked
        transcriptionProviderID = settings.sttProviderID
        transcriptionModelID = settings.sttModelID
        regionID = settings.sttRegionID
        retention = settings.sttRetention
        var sources: [MeetingSourceKind] = []
        if settings.includeSystemAudio {
            sources.append(.systemAudio)
        }
        if settings.includeMicrophone {
            sources.append(.microphone)
        }
        sourceKinds = sources
        diarizationEnabled = settings.sttDiarizationEnabled
        localFallbackEnabled = settings.localFallbackEnabled
        credentialReady = readiness.state == .ready
        notesDestination = settings.isModelConfigured ? settings.modelSelector : nil
    }
}

enum MeetingNotesTimeFormatter {
    static func elapsed(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func transcript(_ milliseconds: Int64) -> String {
        elapsed(TimeInterval(max(0, milliseconds)) / 1000)
    }

    static func transcript(_ milliseconds: Int64, relativeTo captureStartMilliseconds: Int64) -> String {
        transcript(max(0, milliseconds - captureStartMilliseconds))
    }

    static func date(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

struct MeetingNotesSynthesisPresentation: Equatable {
    let title: String
    let detail: String
    let kind: Kind
    let canRetry: Bool
    let shouldOpenSettings: Bool

    enum Kind: Equatable {
        case neutral
        case active
        case warning
        case error
        case success
    }

    static func resolve(_ state: MeetingSynthesisState) -> Self {
        switch state.status {
        case .idle:
            return Self(
                title: "Waiting for transcript",
                detail: "Notes will be scheduled after final transcript segments are available.",
                kind: .neutral,
                canRetry: false,
                shouldOpenSettings: false
            )
        case .scheduled:
            return Self(
                title: "Notes scheduled",
                detail: "Final transcript segments are queued for the selected notes model.",
                kind: .neutral,
                canRetry: state.isPending,
                shouldOpenSettings: false
            )
        case .generating:
            return Self(
                title: "Generating notes",
                detail: "The selected model is processing final transcript segments now.",
                kind: .active,
                canRetry: false,
                shouldOpenSettings: false
            )
        case .retryScheduled:
            return Self(
                title: "Notes retry scheduled",
                detail: retryDetail(state.nextAttemptAtMilliseconds),
                kind: .warning,
                canRetry: state.isPending,
                shouldOpenSettings: false
            )
        case .failed:
            let errorCode = state.lastErrorCode
            return Self(
                title: "Notes generation failed",
                detail: failureReason(errorCode),
                kind: .error,
                canRetry: state.isPending,
                shouldOpenSettings: errorCode?.isConfigurationFailure == true
            )
        case .completed:
            return Self(
                title: "Notes complete",
                detail: "All final transcript segments have been incorporated into these notes.",
                kind: .success,
                canRetry: false,
                shouldOpenSettings: false
            )
        }
    }

    static func failureReason(_ code: MeetingSynthesisErrorCode?) -> String {
        switch code {
        case .invalidRequest:
            "The saved notes request is not supported by the current runtime. Review the notes model configuration."
        case .modelUnavailable:
            "The selected notes model is unavailable. Choose an available model in Meeting Notes settings."
        case .credentialUnavailable:
            "Authentication for the selected notes model is unavailable. Update it in Meeting Notes settings."
        case .providerTimeout:
            "The notes provider timed out before completing this attempt."
        case .providerFailure:
            "The notes provider could not complete this attempt."
        case .invalidResponse:
            "The notes provider returned a response Kaji could not safely apply."
        case .cancelled:
            "The notes attempt was cancelled before it completed."
        case nil:
            "The notes attempt did not complete. Retry when the selected model is available."
        }
    }

    private static func retryDetail(_ nextAttemptAtMilliseconds: Int64?) -> String {
        guard let nextAttemptAtMilliseconds else {
            return "Kaji will retry when the notes provider is available."
        }
        return "Next automatic attempt: \(MeetingNotesTimeFormatter.date(nextAttemptAtMilliseconds))."
    }
}

extension MeetingSynthesisErrorCode {
    var isConfigurationFailure: Bool {
        switch self {
        case .invalidRequest,
             .modelUnavailable,
             .credentialUnavailable:
            true
        case .providerTimeout,
             .providerFailure,
             .invalidResponse,
             .cancelled:
            false
        }
    }
}

extension MeetingLifecyclePhase {
    var meetingNotesTitle: String {
        switch self {
        case .ready:
            "Ready"
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .completed:
            "Completed"
        case .interrupted:
            "Interrupted"
        }
    }
}

struct MeetingNotesStatusPresentation: Equatable {
    let title: String
    let detail: String?
    let kind: Kind

    enum Kind: Equatable {
        case neutral
        case active
        case warning
        case error
    }

    static func resolve(_ status: MeetingNotesCoordinatorStatus) -> Self? {
        switch status {
        case .unconfigured:
            Self(title: "Setup required", detail: "Meeting notes need the app environment before use.", kind: .warning)
        case .loading:
            Self(title: "Loading meetings", detail: nil, kind: .neutral)
        case .preparing:
            Self(title: "Checking local transcription configuration", detail: nil, kind: .neutral)
        case .choosingApplication:
            Self(title: "Choose an application", detail: "Select the application whose audio you are authorized to record.", kind: .neutral)
        case .starting:
            Self(title: "Starting capture", detail: nil, kind: .active)
        case .recording:
            Self(title: "Recording", detail: "Audio capture and the selected transcription route are active.", kind: .active)
        case .stopping:
            Self(title: "Stopping recording", detail: "Finishing buffered transcription.", kind: .neutral)
        case .synthesizing:
            Self(title: "Updating notes", detail: "Final transcript segments are being processed.", kind: .neutral)
        case .completed:
            Self(title: "Meeting complete", detail: nil, kind: .neutral)
        case let .unavailable(message):
            Self(title: "Unavailable", detail: message, kind: .warning)
        case let .failed(message):
            Self(title: "Meeting notes error", detail: message, kind: .error)
        case .idle:
            nil
        }
    }
}
