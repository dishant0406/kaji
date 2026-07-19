import Foundation

struct MeetingNotesSynthesisRequest: Codable, Equatable {
    let requestID: UUID
    let sessionID: UUID
    let transcriptRevision: Int
    let transcriptSegments: [MeetingTranscriptSegment]
    let currentNotes: MeetingNotesSnapshot
    let projectContext: MeetingProjectContext?
    let sourceKindsByTrackID: [UUID: MeetingSourceKind]
    let sourceLabelsByTrackID: [UUID: String]
    let providerID: String
    let modelID: String
    let styleInstructions: String
    let allowedProjectIDs: [UUID]

    init(
        requestID: UUID = UUID(),
        sessionID: UUID,
        transcriptRevision: Int,
        transcriptSegments: [MeetingTranscriptSegment],
        currentNotes: MeetingNotesSnapshot,
        projectContext: MeetingProjectContext?,
        sourceKindsByTrackID: [UUID: MeetingSourceKind] = [:],
        sourceLabelsByTrackID: [UUID: String] = [:],
        providerID: String = "",
        modelID: String = "",
        styleInstructions: String = "",
        allowedProjectIDs: [UUID] = []
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.transcriptRevision = transcriptRevision
        self.transcriptSegments = transcriptSegments
        self.currentNotes = currentNotes
        self.projectContext = projectContext
        self.sourceKindsByTrackID = sourceKindsByTrackID
        self.sourceLabelsByTrackID = sourceLabelsByTrackID
        self.providerID = providerID
        self.modelID = modelID
        self.styleInstructions = styleInstructions
        self.allowedProjectIDs = allowedProjectIDs
    }
}

@MainActor
protocol MeetingNotesSynthesizing: AnyObject {
    func synthesizeNotes(for request: MeetingNotesSynthesisRequest) async throws -> MeetingNotesPatch
}

enum MeetingNotesSynthesisValidationError: Error, Equatable {
    case sessionMismatch
    case invalidTranscriptRevision
    case tooManyTranscriptSegments
    case transcriptTooLarge
}

struct MeetingNotesSynthesisRequestValidator {
    var maximumTranscriptSegments = 10000
    var maximumTranscriptCharacters = 1_000_000

    func validate(_ request: MeetingNotesSynthesisRequest) throws {
        guard request.sessionID == request.currentNotes.sessionID else {
            throw MeetingNotesSynthesisValidationError.sessionMismatch
        }
        guard request.transcriptRevision >= 0 else {
            throw MeetingNotesSynthesisValidationError.invalidTranscriptRevision
        }
        guard request.transcriptSegments.count <= maximumTranscriptSegments else {
            throw MeetingNotesSynthesisValidationError.tooManyTranscriptSegments
        }
        let characterCount = request.transcriptSegments.reduce(0) { partial, segment in
            let (sum, overflow) = partial.addingReportingOverflow(segment.text.count)
            return overflow ? Int.max : sum
        }
        guard characterCount <= maximumTranscriptCharacters else {
            throw MeetingNotesSynthesisValidationError.transcriptTooLarge
        }
    }
}
