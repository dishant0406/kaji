import Foundation

@MainActor
final class KajiMeetingNotesAgentClient: MeetingNotesSynthesizing, MeetingNotesModelValidating {
    private let timeoutMilliseconds: Int64
    private let commandRunner: KajiCodeCLICommandRunning
    private let environment: [String: String]
    private let validator = MeetingNotesSynthesisRequestValidator()

    init(
        timeoutMilliseconds: Int64 = 120_000,
        commandRunner: KajiCodeCLICommandRunning = KajiCodeCLICommandRunner(),
        environment: [String: String] = ShellExecutionEnvironmentResolver.resolve()
    ) {
        self.timeoutMilliseconds = timeoutMilliseconds
        self.commandRunner = commandRunner
        self.environment = environment
    }

    func synthesizeNotes(for request: MeetingNotesSynthesisRequest) async throws -> MeetingNotesPatch {
        try validator.validate(request)
        guard validSelector(request.providerID, maximum: 64),
              validSelector(request.modelID, maximum: 192),
              request.styleInstructions.count <= 2000,
              request.allowedProjectIDs.count <= 20,
              Set(request.allowedProjectIDs).count == request.allowedProjectIDs.count,
              let binaryURL = resolvedBinaryURL()
        else {
            throw KajiMeetingNotesAgentError.unavailable
        }
        let payload = try makePayloadJSON(request)
        let prompt = Self.synthesisPrompt(payload: payload, modelID: request.modelID)
        let output = try await runKajicode(
            binaryURL: binaryURL,
            arguments: ["-p", prompt]
        )
        let patchValue = try Self.patchValue(from: output)
        do {
            return try MeetingNotesRuntimePatchConverter().convert(
                patchValue,
                sessionID: request.sessionID,
                expectedBaseRevision: request.currentNotes.revision,
                transcriptSegments: request.transcriptSegments,
                allowedProjectIDs: Set(request.allowedProjectIDs)
            )
        } catch {
            throw KajiMeetingNotesAgentError.invalidResponse
        }
    }

    func validateModel(providerID: String, modelID: String) async -> MeetingNotesModelReadiness {
        guard validSelector(providerID, maximum: 64),
              validSelector(modelID, maximum: 192)
        else {
            return .unavailable(.unavailable)
        }
        guard resolvedBinaryURL() != nil else {
            return .unavailable(.unavailable)
        }
        return .ready
    }

    private func makePayloadJSON(_ request: MeetingNotesSynthesisRequest) throws -> String {
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
        let encoded = try JSONEncoder().encode(payload)
        return String(decoding: encoded, as: UTF8.self)
    }

    private func resolvedBinaryURL() -> URL? {
        KajiCodeRuntimeLocator.resolve(env: environment)?.binaryURL
    }

    private func runKajicode(binaryURL: URL, arguments: [String]) async throws -> String {
        let runner = commandRunner
        let env = environment
        let timeout = TimeInterval(timeoutMilliseconds / 1000)
        nonisolated(unsafe) let unsafeBinary = binaryURL
        nonisolated(unsafe) let unsafeArgs = arguments
        return try await Task.detached(priority: .userInitiated) {
            let result = try runner.run(
                binaryURL: unsafeBinary,
                arguments: unsafeArgs,
                environment: env,
                timeout: timeout
            )
            guard result.exitCode == 0 else {
                throw KajiMeetingNotesAgentError.failed
            }
            return result.output
        }.value
    }

    static func patchValue(from output: String) throws -> KajiAgentJSONValue {
        guard let jsonStart = output.firstIndex(of: "{") else {
            throw KajiMeetingNotesAgentError.invalidResponse
        }
        let jsonText = String(output[jsonStart...])
        guard let data = jsonText.data(using: .utf8),
              let value = try? JSONDecoder().decode(KajiAgentJSONValue.self, from: data),
              value.objectValue?["operations"] != nil
        else {
            throw KajiMeetingNotesAgentError.invalidResponse
        }
        return value
    }

    static func synthesisPrompt(payload: String, modelID: String) -> String {
        [
            "You are updating structured meeting notes.",
            "Return ONLY a JSON patch object. No markdown, no explanation, no code fences.",
            "The JSON must have exactly these top-level keys:",
            "baseRevision, coveredStartMilliseconds, coveredEndMilliseconds, operations.",
            "Keep baseRevision unchanged from the payload. Operations use these names:",
            "set_title, set_summary, set_linked_projects, upsert_decision, remove_decision,",
            "upsert_action_item, remove_action_item, upsert_open_question, remove_open_question,",
            "upsert_risk, remove_risk. Limit operations to 100.",
            "Reference evidence with evidenceIds pointing at transcript segment ids from the payload.",
            "Model to simulate: \(modelID).",
            "",
            "Payload JSON:",
            payload,
        ].joined(separator: "\n")
    }

    private func validSelector(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= maximum && value.allSatisfy { character in
            character.asciiValue.map { $0 >= 0x21 && $0 <= 0x7E } ?? false
        }
    }
}

private func optionalString(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
}

enum MeetingTranscriptOrdering {
    static func areInIncreasingOrder(_ lhs: MeetingTranscriptSegment, _ rhs: MeetingTranscriptSegment) -> Bool {
        if lhs.startMilliseconds != rhs.startMilliseconds {
            return lhs.startMilliseconds < rhs.startMilliseconds
        }
        if lhs.endMilliseconds != rhs.endMilliseconds {
            return lhs.endMilliseconds < rhs.endMilliseconds
        }
        if lhs.trackID != rhs.trackID {
            return lhs.trackID.uuidString < rhs.trackID.uuidString
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
