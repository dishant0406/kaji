import Foundation

enum MeetingNotesReducerError: Error, Equatable {
    case sessionMismatch
    case staleBaseRevision
    case emptyPatch
    case tooManyOperations
    case invalidText
    case invalidTimestamp
    case invalidEvidence
    case projectNotAllowed
    case duplicateIdentifier
    case itemLimitExceeded
    case pinnedItemProtected
    case pinMutationNotAllowed
    case itemNotFound
}

struct MeetingNotesReducerLimits {
    var maximumOperations = 100
    var maximumTitleLength = 200
    var maximumSummaryLength = 20000
    var maximumItemTextLength = 2000
    var maximumOwnerLength = 200
    var maximumMitigationLength = 2000
    var maximumEvidenceQuoteLength = 500
    var maximumEvidencePerItem = 8
    var maximumItemsPerCategory = 200
    var maximumLinkedProjects = 20
}

struct MeetingNotesReducer {
    let limits: MeetingNotesReducerLimits

    init(limits: MeetingNotesReducerLimits = MeetingNotesReducerLimits()) {
        self.limits = limits
    }

    func applying(
        _ patch: MeetingNotesPatch,
        to snapshot: MeetingNotesSnapshot,
        transcriptSegments: [MeetingTranscriptSegment],
        allowedProjectIDs: Set<UUID>,
        atMilliseconds: Int64
    ) throws -> MeetingNotesSnapshot {
        guard patch.sessionID == snapshot.sessionID else { throw MeetingNotesReducerError.sessionMismatch }
        guard patch.baseRevision == snapshot.revision else { throw MeetingNotesReducerError.staleBaseRevision }
        guard !patch.operations.isEmpty else { throw MeetingNotesReducerError.emptyPatch }
        guard patch.operations.count <= limits.maximumOperations else {
            throw MeetingNotesReducerError.tooManyOperations
        }
        guard atMilliseconds >= snapshot.updatedAtMilliseconds else { throw MeetingNotesReducerError.invalidTimestamp }
        let transcriptByID = Dictionary(uniqueKeysWithValues: transcriptSegments.map { ($0.id, $0) })
        guard transcriptByID.count == transcriptSegments.count else { throw MeetingNotesReducerError.duplicateIdentifier }
        var result = snapshot
        for operation in patch.operations {
            try apply(operation, to: &result)
        }
        result.revision += 1
        result.updatedAtMilliseconds = atMilliseconds
        try validateSnapshot(
            result,
            transcriptSegmentsByID: transcriptByID,
            allowedProjectIDs: allowedProjectIDs
        )
        return result
    }

    func validateSnapshot(
        _ snapshot: MeetingNotesSnapshot,
        transcriptSegments: [MeetingTranscriptSegment],
        allowedProjectIDs: Set<UUID>
    ) throws {
        let transcriptByID = Dictionary(uniqueKeysWithValues: transcriptSegments.map { ($0.id, $0) })
        guard transcriptByID.count == transcriptSegments.count else { throw MeetingNotesReducerError.duplicateIdentifier }
        try validateSnapshot(
            snapshot,
            transcriptSegmentsByID: transcriptByID,
            allowedProjectIDs: allowedProjectIDs
        )
    }

    private func apply(_ operation: MeetingNotesPatchOperation, to snapshot: inout MeetingNotesSnapshot) throws {
        switch operation {
        case let .setTitle(title):
            snapshot.title = title
        case let .setSummary(summary):
            snapshot.summary = summary
        case let .setLinkedProjects(projectIDs):
            snapshot.linkedProjectIDs = projectIDs
        case let .upsertDecision(item):
            try upsert(item, in: &snapshot.decisions)
        case let .removeDecision(id):
            try remove(id, from: &snapshot.decisions)
        case let .upsertActionItem(item):
            try upsert(item, in: &snapshot.actionItems)
        case let .removeActionItem(id):
            try remove(id, from: &snapshot.actionItems)
        case let .upsertOpenQuestion(item):
            try upsert(item, in: &snapshot.openQuestions)
        case let .removeOpenQuestion(id):
            try remove(id, from: &snapshot.openQuestions)
        case let .upsertRisk(item):
            try upsert(item, in: &snapshot.risks)
        case let .removeRisk(id):
            try remove(id, from: &snapshot.risks)
        }
    }

    private func upsert(_ item: MeetingDecision, in items: inout [MeetingDecision]) throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            guard items[index].isPinned == item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
            items[index] = item
            return
        }
        guard !item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
        items.append(item)
    }

    private func upsert(_ item: MeetingActionItem, in items: inout [MeetingActionItem]) throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            guard items[index].isPinned == item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
            items[index] = item
            return
        }
        guard !item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
        items.append(item)
    }

    private func upsert(_ item: MeetingOpenQuestion, in items: inout [MeetingOpenQuestion]) throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            guard items[index].isPinned == item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
            items[index] = item
            return
        }
        guard !item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
        items.append(item)
    }

    private func upsert(_ item: MeetingRisk, in items: inout [MeetingRisk]) throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            guard items[index].isPinned == item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
            items[index] = item
            return
        }
        guard !item.isPinned else { throw MeetingNotesReducerError.pinMutationNotAllowed }
        items.append(item)
    }

    private func remove(_ id: UUID, from items: inout [MeetingDecision]) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw MeetingNotesReducerError.itemNotFound }
        guard !items[index].isPinned else { throw MeetingNotesReducerError.pinnedItemProtected }
        items.remove(at: index)
    }

    private func remove(_ id: UUID, from items: inout [MeetingActionItem]) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw MeetingNotesReducerError.itemNotFound }
        guard !items[index].isPinned else { throw MeetingNotesReducerError.pinnedItemProtected }
        items.remove(at: index)
    }

    private func remove(_ id: UUID, from items: inout [MeetingOpenQuestion]) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw MeetingNotesReducerError.itemNotFound }
        guard !items[index].isPinned else { throw MeetingNotesReducerError.pinnedItemProtected }
        items.remove(at: index)
    }

    private func remove(_ id: UUID, from items: inout [MeetingRisk]) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw MeetingNotesReducerError.itemNotFound }
        guard !items[index].isPinned else { throw MeetingNotesReducerError.pinnedItemProtected }
        items.remove(at: index)
    }

    private func validateSnapshot(
        _ snapshot: MeetingNotesSnapshot,
        transcriptSegmentsByID: [UUID: MeetingTranscriptSegment],
        allowedProjectIDs: Set<UUID>
    ) throws {
        guard snapshot.revision >= 0, snapshot.updatedAtMilliseconds >= 0 else {
            throw MeetingNotesReducerError.invalidTimestamp
        }
        try validateRequiredText(snapshot.title, maximum: limits.maximumTitleLength)
        try validateOptionalText(snapshot.summary, maximum: limits.maximumSummaryLength)
        guard snapshot.linkedProjectIDs.count <= limits.maximumLinkedProjects,
              Set(snapshot.linkedProjectIDs).count == snapshot.linkedProjectIDs.count
        else {
            throw MeetingNotesReducerError.duplicateIdentifier
        }
        guard Set(snapshot.linkedProjectIDs).isSubset(of: allowedProjectIDs) else {
            throw MeetingNotesReducerError.projectNotAllowed
        }
        try validateCountAndIDs(snapshot.decisions)
        try validateCountAndIDs(snapshot.actionItems)
        try validateCountAndIDs(snapshot.openQuestions)
        try validateCountAndIDs(snapshot.risks)
        for item in snapshot.decisions {
            try validateRequiredText(item.text, maximum: limits.maximumItemTextLength)
            try validate(item.evidence, transcriptSegmentsByID: transcriptSegmentsByID)
        }
        for item in snapshot.actionItems {
            try validateRequiredText(item.text, maximum: limits.maximumItemTextLength)
            if let owner = item.owner {
                try validateRequiredText(owner, maximum: limits.maximumOwnerLength)
            }
            if let dueAtMilliseconds = item.dueAtMilliseconds {
                guard dueAtMilliseconds >= 0 else { throw MeetingNotesReducerError.invalidTimestamp }
            }
            try validate(item.evidence, transcriptSegmentsByID: transcriptSegmentsByID)
        }
        for item in snapshot.openQuestions {
            try validateRequiredText(item.text, maximum: limits.maximumItemTextLength)
            try validate(item.evidence, transcriptSegmentsByID: transcriptSegmentsByID)
        }
        for item in snapshot.risks {
            try validateRequiredText(item.text, maximum: limits.maximumItemTextLength)
            if let mitigation = item.mitigation {
                try validateRequiredText(mitigation, maximum: limits.maximumMitigationLength)
            }
            try validate(item.evidence, transcriptSegmentsByID: transcriptSegmentsByID)
        }
    }

    private func validate(
        _ evidenceItems: [MeetingEvidence],
        transcriptSegmentsByID: [UUID: MeetingTranscriptSegment]
    ) throws {
        guard evidenceItems.count <= limits.maximumEvidencePerItem,
              Set(evidenceItems).count == evidenceItems.count
        else {
            throw MeetingNotesReducerError.invalidEvidence
        }
        for evidence in evidenceItems {
            guard let segment = transcriptSegmentsByID[evidence.transcriptSegmentID],
                  !evidence.exactQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  evidence.exactQuote.count <= limits.maximumEvidenceQuoteLength,
                  segment.text.localizedCaseInsensitiveContains(evidence.exactQuote)
            else {
                throw MeetingNotesReducerError.invalidEvidence
            }
        }
    }

    private func validateCountAndIDs<T: Identifiable>(_ items: [T]) throws where T.ID == UUID {
        guard items.count <= limits.maximumItemsPerCategory else { throw MeetingNotesReducerError.itemLimitExceeded }
        guard Set(items.map(\.id)).count == items.count else { throw MeetingNotesReducerError.duplicateIdentifier }
    }

    private func validateRequiredText(_ text: String, maximum: Int) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= maximum,
              !text.contains("\0")
        else {
            throw MeetingNotesReducerError.invalidText
        }
    }

    private func validateOptionalText(_ text: String, maximum: Int) throws {
        guard text.count <= maximum, !text.contains("\0") else { throw MeetingNotesReducerError.invalidText }
    }
}
