import Foundation

enum KajiMeetingNotesAgentError: LocalizedError, Equatable {
    case unavailable
    case invalidRequest
    case modelUnavailable
    case credentialUnavailable
    case timedOut
    case readinessTimedOut
    case failed
    case invalidResponse
    case cancelled

    var synthesisCode: MeetingSynthesisErrorCode {
        switch self {
        case .invalidRequest: .invalidRequest
        case .unavailable,
             .modelUnavailable: .modelUnavailable
        case .credentialUnavailable: .credentialUnavailable
        case .timedOut,
             .readinessTimedOut: .providerTimeout
        case .failed: .providerFailure
        case .invalidResponse: .invalidResponse
        case .cancelled: .cancelled
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The meeting notes request is incompatible with the runtime."
        case .unavailable,
             .modelUnavailable:
            "The configured meeting notes model is unavailable."
        case .credentialUnavailable:
            "The configured meeting notes model requires authentication."
        case .timedOut:
            "Meeting notes synthesis timed out."
        case .readinessTimedOut:
            "The Kaji runtime did not respond to notes model validation."
        case .failed:
            "The notes provider could not complete synthesis."
        case .invalidResponse:
            "Meeting notes synthesis returned an invalid response."
        case .cancelled:
            "Meeting notes synthesis was cancelled."
        }
    }

    init(code: String?) {
        switch code {
        case MeetingSynthesisErrorCode.invalidRequest.rawValue: self = .invalidRequest
        case MeetingSynthesisErrorCode.modelUnavailable.rawValue: self = .modelUnavailable
        case MeetingSynthesisErrorCode.credentialUnavailable.rawValue: self = .credentialUnavailable
        case MeetingSynthesisErrorCode.providerTimeout.rawValue: self = .timedOut
        case MeetingSynthesisErrorCode.invalidResponse.rawValue: self = .invalidResponse
        case MeetingSynthesisErrorCode.cancelled.rawValue: self = .cancelled
        default: self = .failed
        }
    }
}

enum MeetingNotesModelReadiness: Equatable {
    case unchecked
    case checking
    case ready
    case unavailable(KajiMeetingNotesAgentError)

    var isReady: Bool { self == .ready }

    var title: String {
        switch self {
        case .unchecked: "Not checked"
        case .checking: "Checking"
        case .ready: "Ready"
        case .unavailable: "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .unchecked: "Select a provider and model to verify availability and authentication."
        case .checking: "Verifying the selected model without sending a completion request."
        case .ready: "The selected model and its authentication are available."
        case let .unavailable(error): error.localizedDescription
        }
    }
}

@MainActor
protocol MeetingNotesModelValidating: AnyObject {
    func validateModel(providerID: String, modelID: String) async -> MeetingNotesModelReadiness
}

struct KajiMeetingNotesRequestPayload: Encodable {
    struct CanonicalNotes: Encodable {
        let revision: Int
        let title: String
        let summary: String
        let linkedProjectIds: [UUID]
        let decisions: [Decision]
        let actionItems: [ActionItem]
        let openQuestions: [OpenQuestion]
        let risks: [Risk]

        init(_ notes: MeetingNotesSnapshot) {
            revision = notes.revision
            title = notes.title
            summary = String(notes.summary.prefix(20000))
            linkedProjectIds = Array(notes.linkedProjectIDs.prefix(20))
            decisions = notes.decisions.prefix(50).map(Decision.init)
            actionItems = notes.actionItems.prefix(50).map(ActionItem.init)
            openQuestions = notes.openQuestions.prefix(50).map(OpenQuestion.init)
            risks = notes.risks.prefix(50).map(Risk.init)
        }
    }

    struct Evidence: Encodable {
        let transcriptSegmentId: UUID
        let exactQuote: String

        init(_ evidence: MeetingEvidence) {
            transcriptSegmentId = evidence.transcriptSegmentID
            exactQuote = evidence.exactQuote
        }
    }

    struct Decision: Encodable {
        let id: UUID
        let text: String
        let evidence: [Evidence]
        let isPinned: Bool

        init(_ item: MeetingDecision) {
            id = item.id
            text = item.text
            evidence = item.evidence.map(Evidence.init)
            isPinned = item.isPinned
        }
    }

    struct ActionItem: Encodable {
        let id: UUID
        let text: String
        let owner: String?
        let dueAtMilliseconds: Int64?
        let isCompleted: Bool
        let evidence: [Evidence]
        let isPinned: Bool

        init(_ item: MeetingActionItem) {
            id = item.id
            text = item.text
            owner = item.owner
            dueAtMilliseconds = item.dueAtMilliseconds
            isCompleted = item.isCompleted
            evidence = item.evidence.map(Evidence.init)
            isPinned = item.isPinned
        }
    }

    struct OpenQuestion: Encodable {
        let id: UUID
        let text: String
        let isResolved: Bool
        let evidence: [Evidence]
        let isPinned: Bool

        init(_ item: MeetingOpenQuestion) {
            id = item.id
            text = item.text
            isResolved = item.isResolved
            evidence = item.evidence.map(Evidence.init)
            isPinned = item.isPinned
        }
    }

    struct Risk: Encodable {
        let id: UUID
        let text: String
        let mitigation: String?
        let severity: MeetingRiskSeverity
        let evidence: [Evidence]
        let isPinned: Bool

        init(_ item: MeetingRisk) {
            id = item.id
            text = item.text
            mitigation = item.mitigation
            severity = item.severity
            evidence = item.evidence.map(Evidence.init)
            isPinned = item.isPinned
        }
    }

    struct Transcript: Encodable {
        let id: UUID
        let source: MeetingSourceKind
        let sourceLabel: String?
        let speakerLabel: String?
        let startMilliseconds: Int64
        let endMilliseconds: Int64
        let text: String
    }

    struct ProjectContext: Encodable {
        let projectId: UUID
        let name: String
        let summary: String
        let recentRelativeFilePaths: [String]

        init(_ project: MeetingProjectContext.Project) {
            projectId = project.projectID
            name = project.name
            summary = project.summary
            recentRelativeFilePaths = project.recentRelativeFilePaths
        }
    }

    let provider: String
    let modelId: String
    let baseRevision: Int
    let coveredStartMilliseconds: Int64
    let coveredEndMilliseconds: Int64
    let currentCanonicalNotes: CanonicalNotes
    let newTranscriptSegments: [Transcript]
    let projectContexts: [ProjectContext]
    let allowedProjectIds: [UUID]
    let styleInstructions: String?
}
