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
            "The Kaji Agent runtime did not respond to notes model validation."
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

@MainActor
final class KajiMeetingNotesAgentClient: MeetingNotesSynthesizing, MeetingNotesModelValidating {
    private let timeoutMilliseconds: Int64
    private let processFactory: @MainActor () -> KajiAgentProcess
    private let launchResolver: @MainActor () -> KajiAgentLaunchResolution
    private let validator: MeetingNotesSynthesisRequestValidator

    init(
        timeoutMilliseconds: Int64 = 60000,
        processFactory: @escaping @MainActor () -> KajiAgentProcess = KajiAgentProcess.init,
        launchResolver: @escaping @MainActor () -> KajiAgentLaunchResolution = {
            KajiAgentRuntimeLocator.resolveLaunch(
                projectPath: nil,
                approvalMode: KajiAgentPermissionMode.readAllow.rawValue,
                noSession: true,
                noLSP: true,
                noTools: true
            )
        },
        validator: MeetingNotesSynthesisRequestValidator = MeetingNotesSynthesisRequestValidator()
    ) {
        self.timeoutMilliseconds = timeoutMilliseconds
        self.processFactory = processFactory
        self.launchResolver = launchResolver
        self.validator = validator
    }

    func synthesizeNotes(for request: MeetingNotesSynthesisRequest) async throws -> MeetingNotesPatch {
        try validator.validate(request)
        guard validSelector(request.providerID, maximum: 64),
              validSelector(request.modelID, maximum: 192),
              request.styleInstructions.count <= 2000,
              request.allowedProjectIDs.count <= 20,
              Set(request.allowedProjectIDs).count == request.allowedProjectIDs.count,
              case let .ready(launch) = launchResolver()
        else {
            throw KajiMeetingNotesAgentError.unavailable
        }
        let process = processFactory()
        process.launch = launch
        process.approvalMode = KajiAgentPermissionMode.readAllow.rawValue
        process.environmentOverrides = [
            "KAJI_AGENT_ENABLE_MCP": "0",
            "KAJI_AGENT_ENABLE_AUTORESEARCH": "0",
        ]
        let frame = try makeFrame(request)
        let response = KajiMeetingNotesResponseBox(
            process: process,
            commandID: frame.id ?? request.requestID.uuidString,
            request: request
        )
        process.onMessage = { response.handle($0) }
        process.onError = { _ in response.fail(.failed) }
        return try await withTaskCancellationHandler {
            let timeout = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                response.fail(.timedOut)
            }
            defer { timeout.cancel() }
            return try await response.run { process.send(frame) }
        } onCancel: {
            Task { @MainActor in
                response.fail(.cancelled)
                process.stop()
            }
        }
    }

    func validateModel(providerID: String, modelID: String) async -> MeetingNotesModelReadiness {
        guard validSelector(providerID, maximum: 64),
              validSelector(modelID, maximum: 192),
              case let .ready(launch) = launchResolver()
        else {
            return .unavailable(.unavailable)
        }
        let process = processFactory()
        process.launch = launch
        process.approvalMode = KajiAgentPermissionMode.readAllow.rawValue
        process.environmentOverrides = [
            "KAJI_AGENT_ENABLE_MCP": "0",
            "KAJI_AGENT_ENABLE_AUTORESEARCH": "0",
        ]
        let commandID = UUID().uuidString
        let response = KajiMeetingNotesModelReadinessResponseBox(process: process, commandID: commandID)
        process.onMessage = { response.handle($0) }
        process.onError = { _ in response.fail(.failed) }
        let frame = KajiAgentRPCFrame(
            id: commandID,
            type: "validate_meeting_notes_model",
            data: .object(["provider": .string(providerID), "modelId": .string(modelID)])
        )
        return await withTaskCancellationHandler {
            let timeout = Task { @MainActor in
                try await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                response.fail(.readinessTimedOut)
            }
            defer { timeout.cancel() }
            return await response.run { process.send(frame) }
        } onCancel: {
            Task { @MainActor in
                response.fail(.cancelled)
                process.stop()
            }
        }
    }

    func makeFrame(_ request: MeetingNotesSynthesisRequest) throws -> KajiAgentRPCFrame {
        let finalized = request.transcriptSegments.filter(\.isFinal).sorted(by: MeetingTranscriptOrdering.areInIncreasingOrder)
        guard finalized.count <= 128, let first = finalized.first, let last = finalized.last else {
            throw KajiMeetingNotesAgentError.failed
        }
        let payload = KajiMeetingNotesRequestPayload(
            provider: request.providerID,
            modelId: request.modelID,
            baseRevision: request.currentNotes.revision,
            coveredStartMilliseconds: first.startMilliseconds,
            coveredEndMilliseconds: finalized.map(\.endMilliseconds).max() ?? last.endMilliseconds,
            currentCanonicalNotes: .init(request.currentNotes),
            newTranscriptSegments: finalized.map {
                .init(
                    id: $0.id,
                    source: request.sourceKindsByTrackID[$0.trackID] ?? .importedAudio,
                    sourceLabel: request.sourceLabelsByTrackID[$0.trackID],
                    speakerLabel: $0.speakerLabel,
                    startMilliseconds: $0.startMilliseconds,
                    endMilliseconds: $0.endMilliseconds,
                    text: $0.text
                )
            },
            projectContexts: (request.projectContext?.projects ?? []).map(KajiMeetingNotesRequestPayload.ProjectContext.init),
            allowedProjectIds: Array(request.allowedProjectIDs.prefix(20)),
            styleInstructions: optionalString(request.styleInstructions)
        )
        return try KajiAgentRPCFrame(
            id: request.requestID.uuidString,
            type: "generate_meeting_notes",
            data: KajiAgentJSONValue.encode(payload)
        )
    }

    private func validSelector(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= maximum && value.allSatisfy { character in
            character.asciiValue.map { $0 >= 0x21 && $0 <= 0x7E } ?? false
        }
    }
}

private struct KajiMeetingNotesRequestPayload: Encodable {
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

private func optionalString(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
}

@MainActor
final class KajiMeetingNotesResponseBox {
    private let process: KajiAgentProcess
    private let commandID: String
    private let request: MeetingNotesSynthesisRequest
    private var continuation: CheckedContinuation<MeetingNotesPatch, Error>?
    private var completion: Result<MeetingNotesPatch, KajiMeetingNotesAgentError>?

    init(process: KajiAgentProcess, commandID: String, request: MeetingNotesSynthesisRequest) {
        self.process = process
        self.commandID = commandID
        self.request = request
    }

    func run(_ action: () -> Void) async throws -> MeetingNotesPatch {
        try await withCheckedThrowingContinuation { continuation in
            if let completion {
                continuation.resume(with: completion.mapError { $0 as Error })
                return
            }
            self.continuation = continuation
            action()
        }
    }

    func handle(_ frame: KajiAgentRPCFrame) {
        guard completion == nil, frame.id == commandID, frame.type == "response" else { return }
        guard frame.success == true,
              let patchValue = frame.data?.objectValue?["patch"]
        else {
            fail(KajiMeetingNotesAgentError(code: frame.data?.objectValue?["code"]?.stringValue))
            return
        }
        do {
            try succeed(MeetingNotesRuntimePatchConverter().convert(
                patchValue,
                sessionID: request.sessionID,
                expectedBaseRevision: request.currentNotes.revision,
                transcriptSegments: request.transcriptSegments,
                allowedProjectIDs: Set(request.allowedProjectIDs)
            ))
        } catch {
            fail(.invalidResponse)
        }
    }

    func fail(_ error: KajiMeetingNotesAgentError) {
        guard completion == nil else { return }
        completion = .failure(error)
        process.stop()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func succeed(_ patch: MeetingNotesPatch) {
        guard completion == nil else { return }
        completion = .success(patch)
        process.stop()
        continuation?.resume(returning: patch)
        continuation = nil
    }
}

@MainActor
final class KajiMeetingNotesModelReadinessResponseBox {
    private let process: KajiAgentProcess
    private let commandID: String
    private var continuation: CheckedContinuation<MeetingNotesModelReadiness, Never>?
    private var completion: MeetingNotesModelReadiness?

    init(process: KajiAgentProcess, commandID: String) {
        self.process = process
        self.commandID = commandID
    }

    func run(_ action: () -> Void) async -> MeetingNotesModelReadiness {
        await withCheckedContinuation { continuation in
            if let completion {
                continuation.resume(returning: completion)
                return
            }
            self.continuation = continuation
            action()
        }
    }

    func handle(_ frame: KajiAgentRPCFrame) {
        guard completion == nil, frame.id == commandID, frame.type == "response" else { return }
        if frame.success == true {
            complete(.ready)
            return
        }
        fail(KajiMeetingNotesAgentError(code: frame.data?.objectValue?["code"]?.stringValue))
    }

    func fail(_ error: KajiMeetingNotesAgentError) {
        complete(.unavailable(error))
    }

    private func complete(_ readiness: MeetingNotesModelReadiness) {
        guard completion == nil else { return }
        completion = readiness
        process.stop()
        continuation?.resume(returning: readiness)
        continuation = nil
    }
}

extension KajiAgentJSONValue {
    static func encode(_ value: some Encodable) throws -> KajiAgentJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(KajiAgentJSONValue.self, from: data)
    }
}

enum MeetingTranscriptOrdering {
    static func areInIncreasingOrder(_ lhs: MeetingTranscriptSegment, _ rhs: MeetingTranscriptSegment) -> Bool {
        if lhs.startMilliseconds != rhs.startMilliseconds { return lhs.startMilliseconds < rhs.startMilliseconds }
        if lhs.endMilliseconds != rhs.endMilliseconds { return lhs.endMilliseconds < rhs.endMilliseconds }
        if lhs.trackID != rhs.trackID { return lhs.trackID.uuidString < rhs.trackID.uuidString }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
