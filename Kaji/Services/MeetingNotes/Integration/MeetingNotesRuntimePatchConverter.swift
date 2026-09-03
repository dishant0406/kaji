import Foundation

enum MeetingNotesRuntimePatchError: Error, Equatable {
    case invalidPatch
}

struct MeetingNotesRuntimePatchConverter {
    func convert(
        _ value: KajiAgentJSONValue,
        sessionID: UUID,
        expectedBaseRevision: Int,
        transcriptSegments: [MeetingTranscriptSegment],
        allowedProjectIDs: Set<UUID>
    ) throws -> MeetingNotesPatch {
        let object = try exactObject(value, keys: [
            "baseRevision", "coveredStartMilliseconds", "coveredEndMilliseconds", "operations",
        ])
        guard try integer(object["baseRevision"]) == expectedBaseRevision,
              try integer64(object["coveredStartMilliseconds"]) >= 0,
              try integer64(object["coveredEndMilliseconds"]) > 0
        else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        let segmentsByID = Dictionary(uniqueKeysWithValues: transcriptSegments.map { ($0.id, $0) })
        let values = try array(object["operations"])
        guard values.count <= 100 else { throw MeetingNotesRuntimePatchError.invalidPatch }
        let operations = try values.map {
            try operation($0, segmentsByID: segmentsByID, allowedProjectIDs: allowedProjectIDs)
        }
        return MeetingNotesPatch(sessionID: sessionID, baseRevision: expectedBaseRevision, operations: operations)
    }

    private func operation(
        _ value: KajiAgentJSONValue,
        segmentsByID: [UUID: MeetingTranscriptSegment],
        allowedProjectIDs: Set<UUID>
    ) throws -> MeetingNotesPatchOperation {
        guard let object = value.objectValue, let name = object["op"]?.stringValue else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        let common = Set(["op", "evidenceIds"])
        try validateEvidenceIDs(object["evidenceIds"], segmentsByID: segmentsByID)
        switch name {
        case "set_title":
            try requireKeys(object, common.union(["title"]))
            return try .setTitle(requiredString(object["title"], maximum: 200))
        case "set_summary":
            try requireKeys(object, common.union(["summary"]))
            return try .setSummary(optionalString(object["summary"], maximum: 20000))
        case "set_linked_projects":
            try requireKeys(object, common.union(["projectIds"]))
            let ids = try uuidArray(object["projectIds"], maximum: 20)
            guard Set(ids).count == ids.count, Set(ids).isSubset(of: allowedProjectIDs) else {
                throw MeetingNotesRuntimePatchError.invalidPatch
            }
            return .setLinkedProjects(ids)
        case "upsert_decision":
            try requireKeys(object, common.union(["decision"]))
            return try .upsertDecision(decision(object["decision"], segmentsByID: segmentsByID))
        case "remove_decision":
            try requireKeys(object, common.union(["itemId"]))
            return try .removeDecision(uuid(object["itemId"]))
        case "upsert_action_item":
            try requireKeys(object, common.union(["actionItem"]))
            return try .upsertActionItem(actionItem(object["actionItem"], segmentsByID: segmentsByID))
        case "remove_action_item":
            try requireKeys(object, common.union(["itemId"]))
            return try .removeActionItem(uuid(object["itemId"]))
        case "upsert_open_question":
            try requireKeys(object, common.union(["openQuestion"]))
            return try .upsertOpenQuestion(openQuestion(object["openQuestion"], segmentsByID: segmentsByID))
        case "remove_open_question":
            try requireKeys(object, common.union(["itemId"]))
            return try .removeOpenQuestion(uuid(object["itemId"]))
        case "upsert_risk":
            try requireKeys(object, common.union(["risk"]))
            return try .upsertRisk(risk(object["risk"], segmentsByID: segmentsByID))
        case "remove_risk":
            try requireKeys(object, common.union(["itemId"]))
            return try .removeRisk(uuid(object["itemId"]))
        default:
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
    }

    private func decision(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws -> MeetingDecision {
        let object = try exactObject(value, keys: ["id", "text", "evidence"])
        return try MeetingDecision(
            id: uuid(object["id"]),
            text: requiredString(object["text"], maximum: 2000),
            evidence: evidence(object["evidence"], segmentsByID: segmentsByID),
            isPinned: false
        )
    }

    private func actionItem(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws -> MeetingActionItem {
        let object = try exactObject(
            value,
            keys: ["id", "text", "owner", "dueAtMilliseconds", "isCompleted", "evidence"]
        )
        return try MeetingActionItem(
            id: uuid(object["id"]),
            text: requiredString(object["text"], maximum: 2000),
            owner: nullableString(object["owner"], maximum: 200),
            dueAtMilliseconds: nullableInt64(object["dueAtMilliseconds"]),
            isCompleted: boolean(object["isCompleted"]),
            evidence: evidence(object["evidence"], segmentsByID: segmentsByID),
            isPinned: false
        )
    }

    private func openQuestion(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws -> MeetingOpenQuestion {
        let object = try exactObject(value, keys: ["id", "text", "isResolved", "evidence"])
        return try MeetingOpenQuestion(
            id: uuid(object["id"]),
            text: requiredString(object["text"], maximum: 2000),
            isResolved: boolean(object["isResolved"]),
            evidence: evidence(object["evidence"], segmentsByID: segmentsByID),
            isPinned: false
        )
    }

    private func risk(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws -> MeetingRisk {
        let object = try exactObject(value, keys: ["id", "text", "mitigation", "severity", "evidence"])
        guard let severityValue = object["severity"]?.stringValue,
              let severity = MeetingRiskSeverity(rawValue: severityValue)
        else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        return try MeetingRisk(
            id: uuid(object["id"]),
            text: requiredString(object["text"], maximum: 2000),
            mitigation: nullableString(object["mitigation"], maximum: 2000),
            severity: severity,
            evidence: evidence(object["evidence"], segmentsByID: segmentsByID),
            isPinned: false
        )
    }

    private func evidence(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws -> [MeetingEvidence] {
        let values = try array(value)
        guard !values.isEmpty, values.count <= 8 else { throw MeetingNotesRuntimePatchError.invalidPatch }
        let evidence = try values.map { value in
            let object = try exactObject(value, keys: ["transcriptSegmentId", "exactQuote"])
            let id = try uuid(object["transcriptSegmentId"])
            let quote = try requiredString(object["exactQuote"], maximum: 500)
            guard let segment = segmentsByID[id], segment.text.localizedCaseInsensitiveContains(quote) else {
                throw MeetingNotesRuntimePatchError.invalidPatch
            }
            return MeetingEvidence(transcriptSegmentID: id, exactQuote: quote)
        }
        guard Set(evidence).count == evidence.count else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return evidence
    }

    private func validateEvidenceIDs(
        _ value: KajiAgentJSONValue?,
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws {
        let ids = try uuidArray(value, maximum: 8)
        guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ segmentsByID[$0] != nil }) else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
    }

    private func exactObject(
        _ value: KajiAgentJSONValue?,
        keys: Set<String>
    ) throws -> [String: KajiAgentJSONValue] {
        guard let object = value?.objectValue else { throw MeetingNotesRuntimePatchError.invalidPatch }
        try requireKeys(object, keys)
        return object
    }

    private func requireKeys(_ object: [String: KajiAgentJSONValue], _ keys: Set<String>) throws {
        guard Set(object.keys) == keys else { throw MeetingNotesRuntimePatchError.invalidPatch }
    }

    private func array(_ value: KajiAgentJSONValue?) throws -> [KajiAgentJSONValue] {
        guard let array = value?.arrayValue else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return array
    }

    private func requiredString(_ value: KajiAgentJSONValue?, maximum: Int) throws -> String {
        guard let value = value?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= maximum,
              !value.contains("\0")
        else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        return value
    }

    private func optionalString(_ value: KajiAgentJSONValue?, maximum: Int) throws -> String {
        guard let value = value?.stringValue, value.count <= maximum, !value.contains("\0") else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        return value
    }

    private func nullableString(_ value: KajiAgentJSONValue?, maximum: Int) throws -> String? {
        if case .null = value {
            return nil
        }
        return try requiredString(value, maximum: maximum)
    }

    private func uuid(_ value: KajiAgentJSONValue?) throws -> UUID {
        guard let string = value?.stringValue, let id = UUID(uuidString: string) else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        return id
    }

    private func uuidArray(_ value: KajiAgentJSONValue?, maximum: Int) throws -> [UUID] {
        let values = try array(value)
        guard values.count <= maximum else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return try values.map(uuid)
    }

    private func integer(_ value: KajiAgentJSONValue?) throws -> Int {
        let number = try integralNumber(value)
        guard number <= Double(Int.max) else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return Int(number)
    }

    private func integer64(_ value: KajiAgentJSONValue?) throws -> Int64 {
        let number = try integralNumber(value)
        guard number <= Double(Int64.max) else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return Int64(number)
    }

    private func nullableInt64(_ value: KajiAgentJSONValue?) throws -> Int64? {
        if case .null = value {
            return nil
        }
        return try integer64(value)
    }

    private func integralNumber(_ value: KajiAgentJSONValue?) throws -> Double {
        guard let number = value?.numberValue, number.isFinite, number >= 0, number.rounded() == number else {
            throw MeetingNotesRuntimePatchError.invalidPatch
        }
        return number
    }

    private func boolean(_ value: KajiAgentJSONValue?) throws -> Bool {
        guard let value = value?.boolValue else { throw MeetingNotesRuntimePatchError.invalidPatch }
        return value
    }
}
