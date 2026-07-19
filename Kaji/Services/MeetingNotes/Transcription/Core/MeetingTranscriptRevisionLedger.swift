import Foundation

struct MeetingTranscriptRevision: Codable, Hashable, Identifiable {
    let id: UUID
    let eventID: UUID
    let operationID: UUID?
    let sessionID: UUID
    let trackID: UUID
    let source: MeetingTranscriptionSource
    let providerEpoch: MeetingProviderEpoch
    let revision: Int
    let sampleRange: MeetingCanonicalSampleRange
    let text: String
    let confidence: Double?
    let words: [MeetingNormalizedWord]
    let speaker: MeetingNormalizedSpeaker?
    let language: MeetingNormalizedLanguage?
    let isFinal: Bool
    let createdAtMilliseconds: Int64

    init(
        context: MeetingTranscriptionEventContext,
        utterance: MeetingTranscriptionUtterance,
        isFinal: Bool
    ) {
        id = utterance.id
        eventID = context.eventID
        operationID = context.operationID
        sessionID = context.sessionID
        trackID = context.trackID
        source = context.source
        providerEpoch = context.providerEpoch
        revision = utterance.revision
        sampleRange = utterance.sampleRange
        text = utterance.text
        confidence = utterance.confidence
        words = utterance.words
        speaker = utterance.speaker
        language = utterance.language
        self.isFinal = isFinal
        createdAtMilliseconds = utterance.createdAtMilliseconds
    }

    var estimatedByteCount: Int {
        256 + text.utf8.count + words.reduce(0) { result, word in
            result + 96 + word.text.utf8.count + (word.speakerID?.utf8.count ?? 0) +
                (word.languageCode?.utf8.count ?? 0)
        } + (speaker?.id.utf8.count ?? 0) + (speaker?.label.utf8.count ?? 0) +
            (language?.code.utf8.count ?? 0)
    }

    init(
        current: MeetingTranscriptRevision,
        context: MeetingTranscriptionEventContext,
        words: [MeetingNormalizedWord],
        speaker: MeetingNormalizedSpeaker?
    ) {
        id = current.id
        eventID = context.eventID
        operationID = current.operationID
        sessionID = current.sessionID
        trackID = current.trackID
        source = current.source
        providerEpoch = current.providerEpoch
        revision = current.revision + 1
        sampleRange = current.sampleRange
        text = current.text
        confidence = current.confidence
        self.words = words
        self.speaker = speaker
        language = current.language
        isFinal = true
        createdAtMilliseconds = current.createdAtMilliseconds
    }
}

struct MeetingTranscriptUtteranceRecord: Codable, Hashable, Identifiable {
    let id: UUID
    private(set) var revisions: [MeetingTranscriptRevision]
    private(set) var current: MeetingTranscriptRevision

    init(revision: MeetingTranscriptRevision) {
        id = revision.id
        revisions = [revision]
        current = revision
    }

    var isCommitted: Bool {
        current.isFinal
    }

    mutating func append(_ revision: MeetingTranscriptRevision) {
        if revision.revision == current.revision {
            revisions[revisions.count - 1] = revision
        } else {
            revisions.append(revision)
        }
        current = revision
    }

    var estimatedByteCount: Int {
        revisions.reduce(0) { $0 + $1.estimatedByteCount }
    }
}

struct MeetingTranscriptRevisionLedger: Codable, Hashable {
    private(set) var records: [UUID: MeetingTranscriptUtteranceRecord]
    private(set) var processedEventIDs: Set<UUID>
    private(set) var processedEventOrder: [UUID]
    private(set) var activeEpochsByTrack: [UUID: MeetingProviderEpoch]
    private(set) var revisionBytes: Int

    init(
        records: [UUID: MeetingTranscriptUtteranceRecord] = [:],
        processedEventIDs: Set<UUID> = [],
        processedEventOrder: [UUID] = [],
        activeEpochsByTrack: [UUID: MeetingProviderEpoch] = [:]
    ) {
        self.records = records
        self.processedEventIDs = processedEventIDs
        self.processedEventOrder = processedEventOrder.isEmpty ? Array(processedEventIDs) : processedEventOrder
        self.activeEpochsByTrack = activeEpochsByTrack
        revisionBytes = records.values.reduce(0) { $0 + $1.estimatedByteCount }
    }

    func record(id: UUID) -> MeetingTranscriptUtteranceRecord? {
        records[id]
    }

    var currentRevisions: [MeetingTranscriptRevision] {
        records.values.map(\.current)
    }

    mutating func markProcessed(eventID: UUID) {
        if processedEventIDs.insert(eventID).inserted {
            processedEventOrder.append(eventID)
        }
    }

    mutating func pruneProcessedEvents(to maximumCount: Int) {
        guard processedEventOrder.count >= maximumCount else { return }
        let removalCount = processedEventOrder.count - maximumCount + 1
        for eventID in processedEventOrder.prefix(removalCount) {
            processedEventIDs.remove(eventID)
        }
        processedEventOrder.removeFirst(removalCount)
    }

    mutating func setActiveEpoch(_ epoch: MeetingProviderEpoch, trackID: UUID) {
        activeEpochsByTrack[trackID] = epoch
        records = records.filter { _, record in
            record.isCommitted || record.current.trackID != trackID || record.current.providerEpoch >= epoch
        }
        revisionBytes = records.values.reduce(0) { $0 + $1.estimatedByteCount }
    }

    mutating func setRecord(_ record: MeetingTranscriptUtteranceRecord) {
        revisionBytes -= records[record.id]?.estimatedByteCount ?? 0
        records[record.id] = record
        revisionBytes += record.estimatedByteCount
    }
}

enum MeetingTranscriptionBufferPolicy {
    static let maximumProviderEvents = 64
    static let maximumOutstandingRealtimeCommits = 64
    static let maximumLedgerBytes = 32 * 1024 * 1024
}

enum MeetingTranscriptReductionResult: Equatable {
    case applied
    case duplicate
    case outOfOrder
    case staleEpoch
    case finalImmutable
    case ignored
}

struct MeetingTranscriptRevisionReducer {
    private(set) var ledger: MeetingTranscriptRevisionLedger
    let maximumUtterances: Int
    let maximumProcessedEvents: Int
    let maximumRevisionsPerUtterance: Int
    let maximumRevisionBytes: Int

    init(
        ledger: MeetingTranscriptRevisionLedger = MeetingTranscriptRevisionLedger(),
        maximumUtterances: Int = 20000,
        maximumProcessedEvents: Int = 100_000,
        maximumRevisionsPerUtterance: Int = 32,
        maximumRevisionBytes: Int = MeetingTranscriptionBufferPolicy.maximumLedgerBytes
    ) throws {
        guard 1 ... 1_000_000 ~= maximumUtterances,
              1 ... 2_000_000 ~= maximumProcessedEvents,
              1 ... 1000 ~= maximumRevisionsPerUtterance,
              1024 ... 256 * 1024 * 1024 ~= maximumRevisionBytes,
              ledger.records.count <= maximumUtterances,
              ledger.processedEventIDs.count <= maximumProcessedEvents,
              ledger.records.values.allSatisfy({ $0.revisions.count <= maximumRevisionsPerUtterance }),
              ledger.revisionBytes <= maximumRevisionBytes
        else {
            throw MeetingTranscriptionValidationError.invalidValue("transcriptReducer.bounds")
        }
        self.ledger = ledger
        self.maximumUtterances = maximumUtterances
        self.maximumProcessedEvents = maximumProcessedEvents
        self.maximumRevisionsPerUtterance = maximumRevisionsPerUtterance
        self.maximumRevisionBytes = maximumRevisionBytes
    }

    mutating func apply(_ event: MeetingTranscriptionProviderEvent) throws -> MeetingTranscriptReductionResult {
        let context = event.context
        if ledger.processedEventIDs.contains(context.eventID) {
            return .duplicate
        }
        ledger.pruneProcessedEvents(to: maximumProcessedEvents)
        ledger.markProcessed(eventID: context.eventID)
        switch event {
        case let .partial(event):
            guard acceptEpoch(context) else { return .staleEpoch }
            return try apply(context: event.context, utterance: event.utterance, isFinal: false)
        case let .final(event):
            guard acceptEpoch(context) else { return .staleEpoch }
            return try apply(context: event.context, utterance: event.utterance, isFinal: true)
        case let .replacement(event):
            guard acceptEpoch(context) else { return .staleEpoch }
            return try applyReplacement(event)
        case let .metadataAmendment(event):
            guard acceptEpoch(context) else { return .staleEpoch }
            return try applyMetadataAmendment(event)
        case .usage,
             .rateLimit,
             .warning,
             .session,
             .failure:
            return .ignored
        }
    }

    func materializedSegments(
        timelineOriginMilliseconds: Int64 = 0,
        includePartials: Bool = true
    ) throws -> [MeetingTranscriptSegment] {
        guard timelineOriginMilliseconds >= 0 else {
            throw MeetingTranscriptionValidationError.invalidValue("timelineOriginMilliseconds")
        }
        return try ledger.currentRevisions
            .filter { includePartials || $0.isFinal }
            .sorted(by: Self.isOrderedBefore)
            .map { revision in
                let sampleRange = try MeetingSampleRange(
                    startFrame: revision.sampleRange.startFrame,
                    endFrame: revision.sampleRange.endFrame,
                    sampleRateHertz: revision.sampleRange.sampleRateHertz
                )
                let startMilliseconds = try Self.milliseconds(
                    frame: revision.sampleRange.startFrame,
                    sampleRateHertz: revision.sampleRange.sampleRateHertz
                )
                let endMilliseconds = try Self.milliseconds(
                    frame: revision.sampleRange.endFrame,
                    sampleRateHertz: revision.sampleRange.sampleRateHertz
                )
                let absoluteStart = timelineOriginMilliseconds.addingReportingOverflow(startMilliseconds)
                let absoluteEnd = timelineOriginMilliseconds.addingReportingOverflow(endMilliseconds)
                guard !absoluteStart.overflow, !absoluteEnd.overflow else {
                    throw MeetingTranscriptionValidationError.invalidValue("segmentTiming")
                }
                return MeetingTranscriptSegment(
                    id: revision.id,
                    trackID: revision.trackID,
                    sampleRange: sampleRange,
                    startMilliseconds: absoluteStart.partialValue,
                    endMilliseconds: absoluteEnd.partialValue,
                    text: revision.text,
                    speakerLabel: revision.speaker?.label,
                    isFinal: revision.isFinal,
                    createdAtMilliseconds: revision.createdAtMilliseconds
                )
            }
    }

    func materializedSegment(
        id: UUID,
        timelineOriginMilliseconds: Int64 = 0
    ) throws -> MeetingTranscriptSegment? {
        guard timelineOriginMilliseconds >= 0 else {
            throw MeetingTranscriptionValidationError.invalidValue("timelineOriginMilliseconds")
        }
        guard let revision = ledger.record(id: id)?.current else { return nil }
        let sampleRange = try MeetingSampleRange(
            startFrame: revision.sampleRange.startFrame,
            endFrame: revision.sampleRange.endFrame,
            sampleRateHertz: revision.sampleRange.sampleRateHertz
        )
        let startMilliseconds = try Self.milliseconds(
            frame: revision.sampleRange.startFrame,
            sampleRateHertz: revision.sampleRange.sampleRateHertz
        )
        let endMilliseconds = try Self.milliseconds(
            frame: revision.sampleRange.endFrame,
            sampleRateHertz: revision.sampleRange.sampleRateHertz
        )
        let absoluteStart = timelineOriginMilliseconds.addingReportingOverflow(startMilliseconds)
        let absoluteEnd = timelineOriginMilliseconds.addingReportingOverflow(endMilliseconds)
        guard !absoluteStart.overflow, !absoluteEnd.overflow else {
            throw MeetingTranscriptionValidationError.invalidValue("segmentTiming")
        }
        return MeetingTranscriptSegment(
            id: revision.id,
            trackID: revision.trackID,
            sampleRange: sampleRange,
            startMilliseconds: absoluteStart.partialValue,
            endMilliseconds: absoluteEnd.partialValue,
            text: revision.text,
            speakerLabel: revision.speaker?.label,
            isFinal: revision.isFinal,
            createdAtMilliseconds: revision.createdAtMilliseconds
        )
    }

    private mutating func acceptEpoch(_ context: MeetingTranscriptionEventContext) -> Bool {
        guard let activeEpoch = ledger.activeEpochsByTrack[context.trackID] else {
            ledger.setActiveEpoch(context.providerEpoch, trackID: context.trackID)
            return true
        }
        if context.providerEpoch < activeEpoch {
            return false
        }
        if context.providerEpoch > activeEpoch {
            ledger.setActiveEpoch(context.providerEpoch, trackID: context.trackID)
        }
        return true
    }

    private mutating func apply(
        context: MeetingTranscriptionEventContext,
        utterance: MeetingTranscriptionUtterance,
        isFinal: Bool
    ) throws -> MeetingTranscriptReductionResult {
        guard utterance.sampleRange.sampleRateHertz > 0 else {
            throw MeetingTranscriptionValidationError.invalidEvent("utterance.sampleRate")
        }
        let revision = MeetingTranscriptRevision(context: context, utterance: utterance, isFinal: isFinal)
        guard var record = ledger.record(id: utterance.id) else {
            guard ledger.records.count < maximumUtterances else {
                throw MeetingTranscriptionValidationError.invalidEvent("utteranceCapacity")
            }
            let next = MeetingTranscriptUtteranceRecord(revision: revision)
            guard ledger.revisionBytes <= maximumRevisionBytes - next.estimatedByteCount else {
                throw MeetingTranscriptionValidationError.invalidEvent("revisionByteCapacity")
            }
            ledger.setRecord(next)
            return .applied
        }
        guard !record.isCommitted else { return .finalImmutable }
        if utterance.revision < record.current.revision {
            return .outOfOrder
        }
        if utterance.revision == record.current.revision, !isFinal {
            return record.current == revision ? .duplicate : .outOfOrder
        }
        guard utterance.revision == record.current.revision || record.revisions.count < maximumRevisionsPerUtterance else {
            throw MeetingTranscriptionValidationError.invalidEvent("revisionCapacity")
        }
        record.append(revision)
        guard ledger.revisionBytes - (ledger.record(id: record.id)?.estimatedByteCount ?? 0) <=
            maximumRevisionBytes - record.estimatedByteCount
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("revisionByteCapacity")
        }
        ledger.setRecord(record)
        return .applied
    }

    private mutating func applyReplacement(
        _ event: MeetingTranscriptionReplacementEvent
    ) throws -> MeetingTranscriptReductionResult {
        guard let record = ledger.record(id: event.replacesUtteranceID) else {
            return .outOfOrder
        }
        guard !record.isCommitted else { return .finalImmutable }
        guard record.current.revision == event.replacesRevision else { return .outOfOrder }
        return try apply(context: event.context, utterance: event.utterance, isFinal: false)
    }

    private mutating func applyMetadataAmendment(
        _ event: MeetingTranscriptionMetadataAmendmentEvent
    ) throws -> MeetingTranscriptReductionResult {
        guard var record = ledger.record(id: event.utteranceID), record.isCommitted else {
            return .outOfOrder
        }
        guard record.current.revision == event.expectedRevision else { return .outOfOrder }
        guard event.words.count == record.current.words.count else {
            throw MeetingTranscriptionValidationError.invalidEvent("metadataAmendment.words")
        }
        for (original, amended) in zip(record.current.words, event.words) {
            guard original.id == amended.id,
                  original.text == amended.text,
                  original.sampleRange == amended.sampleRange,
                  original.confidence == amended.confidence,
                  original.languageCode == amended.languageCode
            else {
                throw MeetingTranscriptionValidationError.invalidEvent("metadataAmendment.words")
            }
        }
        guard record.revisions.count < maximumRevisionsPerUtterance else {
            throw MeetingTranscriptionValidationError.invalidEvent("revisionCapacity")
        }
        record.append(MeetingTranscriptRevision(
            current: record.current,
            context: event.context,
            words: event.words,
            speaker: event.speaker
        ))
        guard ledger.revisionBytes - (ledger.record(id: record.id)?.estimatedByteCount ?? 0) <=
            maximumRevisionBytes - record.estimatedByteCount
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("revisionByteCapacity")
        }
        ledger.setRecord(record)
        return .applied
    }

    private static func milliseconds(frame: Int64, sampleRateHertz: Int) throws -> Int64 {
        let seconds = frame / Int64(sampleRateHertz)
        let remainder = frame % Int64(sampleRateHertz)
        let wholeMilliseconds = seconds.multipliedReportingOverflow(by: 1000)
        let partialProduct = remainder.multipliedReportingOverflow(by: 1000)
        guard !wholeMilliseconds.overflow, !partialProduct.overflow else {
            throw MeetingTranscriptionValidationError.invalidValue("segmentTiming")
        }
        let result = wholeMilliseconds.partialValue.addingReportingOverflow(
            partialProduct.partialValue / Int64(sampleRateHertz)
        )
        guard !result.overflow else {
            throw MeetingTranscriptionValidationError.invalidValue("segmentTiming")
        }
        return result.partialValue
    }

    private static func isOrderedBefore(_ lhs: MeetingTranscriptRevision, _ rhs: MeetingTranscriptRevision) -> Bool {
        let lhsRate = Int64(lhs.sampleRange.sampleRateHertz)
        let rhsRate = Int64(rhs.sampleRange.sampleRateHertz)
        let lhsSeconds = lhs.sampleRange.startFrame / lhsRate
        let rhsSeconds = rhs.sampleRange.startFrame / rhsRate
        if lhsSeconds != rhsSeconds {
            return lhsSeconds < rhsSeconds
        }
        let lhsRemainder = lhs.sampleRange.startFrame % lhsRate
        let rhsRemainder = rhs.sampleRange.startFrame % rhsRate
        let lhsFraction = lhsRemainder * rhsRate
        let rhsFraction = rhsRemainder * lhsRate
        if lhsFraction != rhsFraction {
            return lhsFraction < rhsFraction
        }
        if lhs.trackID != rhs.trackID {
            return lhs.trackID.uuidString < rhs.trackID.uuidString
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
