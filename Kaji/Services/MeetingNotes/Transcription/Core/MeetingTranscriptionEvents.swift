import Foundation

struct MeetingTranscriptionEventContext: Codable, Hashable {
    let eventID: UUID
    let operationID: UUID?
    let sessionID: UUID
    let trackID: UUID
    let source: MeetingTranscriptionSource
    let providerEpoch: MeetingProviderEpoch
    let sequenceNumber: Int64
    let emittedAtMilliseconds: Int64

    init(
        eventID: UUID,
        operationID: UUID? = nil,
        sessionID: UUID,
        trackID: UUID,
        source: MeetingTranscriptionSource,
        providerEpoch: MeetingProviderEpoch,
        sequenceNumber: Int64,
        emittedAtMilliseconds: Int64
    ) throws {
        guard sequenceNumber >= 0, emittedAtMilliseconds >= 0 else {
            throw MeetingTranscriptionValidationError.invalidEvent("context")
        }
        self.eventID = eventID
        self.operationID = operationID
        self.sessionID = sessionID
        self.trackID = trackID
        self.source = source
        self.providerEpoch = providerEpoch
        self.sequenceNumber = sequenceNumber
        self.emittedAtMilliseconds = emittedAtMilliseconds
    }
}

struct MeetingNormalizedWord: Codable, Hashable, Identifiable {
    let id: UUID
    let text: String
    let sampleRange: MeetingCanonicalSampleRange?
    let confidence: Double?
    let speakerID: String?
    let languageCode: String?

    init(
        id: UUID,
        text: String,
        sampleRange: MeetingCanonicalSampleRange? = nil,
        confidence: Double? = nil,
        speakerID: String? = nil,
        languageCode: String? = nil
    ) throws {
        self.id = id
        self.text = try MeetingTranscriptionValidation.normalizedText(text, field: "word.text", maximumLength: 1000)
        guard confidence.map({ $0.isFinite && 0 ... 1 ~= $0 }) ?? true,
              languageCode.map(MeetingTranscriptionValidation.isValidLanguageCode) ?? true
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("word.metadata")
        }
        self.sampleRange = sampleRange
        self.confidence = confidence
        self.speakerID = try speakerID.map {
            try MeetingTranscriptionValidation.normalizedIdentifier($0, field: "word.speakerID")
        }
        self.languageCode = languageCode
    }
}

struct MeetingNormalizedSpeaker: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let confidence: Double?

    init(id: String, label: String, confidence: Double? = nil) throws {
        self.id = try MeetingTranscriptionValidation.normalizedIdentifier(id, field: "speaker.id")
        self.label = try MeetingTranscriptionValidation.normalizedText(label, field: "speaker.label", maximumLength: 120)
        guard confidence.map({ $0.isFinite && 0 ... 1 ~= $0 }) ?? true else {
            throw MeetingTranscriptionValidationError.invalidEvent("speaker.confidence")
        }
        self.confidence = confidence
    }
}

struct MeetingNormalizedLanguage: Codable, Hashable {
    let code: String
    let confidence: Double?

    init(code: String, confidence: Double? = nil) throws {
        guard MeetingTranscriptionValidation.isValidLanguageCode(code),
              confidence.map({ $0.isFinite && 0 ... 1 ~= $0 }) ?? true
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("language")
        }
        self.code = code
        self.confidence = confidence
    }
}

struct MeetingTranscriptionUtterance: Codable, Hashable, Identifiable {
    let id: UUID
    let revision: Int
    let sampleRange: MeetingCanonicalSampleRange
    let text: String
    let confidence: Double?
    let words: [MeetingNormalizedWord]
    let speaker: MeetingNormalizedSpeaker?
    let language: MeetingNormalizedLanguage?
    let createdAtMilliseconds: Int64

    init(
        id: UUID,
        revision: Int,
        sampleRange: MeetingCanonicalSampleRange,
        text: String,
        confidence: Double? = nil,
        words: [MeetingNormalizedWord] = [],
        speaker: MeetingNormalizedSpeaker? = nil,
        language: MeetingNormalizedLanguage? = nil,
        createdAtMilliseconds: Int64
    ) throws {
        guard revision >= 0,
              confidence.map({ $0.isFinite && 0 ... 1 ~= $0 }) ?? true,
              words.count <= 10000,
              Set(words.map(\.id)).count == words.count,
              createdAtMilliseconds >= 0
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("utterance.metadata")
        }
        let normalizedText = try MeetingTranscriptionValidation.normalizedText(
            text,
            field: "utterance.text",
            maximumLength: 100_000
        )
        guard words.allSatisfy({ word in
            guard let range = word.sampleRange else { return true }
            return range.sampleRateHertz == sampleRange.sampleRateHertz &&
                range.startFrame >= sampleRange.startFrame &&
                range.endFrame <= sampleRange.endFrame
        })
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("utterance.words")
        }
        self.id = id
        self.revision = revision
        self.sampleRange = sampleRange
        self.text = normalizedText
        self.confidence = confidence
        self.words = words
        self.speaker = speaker
        self.language = language
        self.createdAtMilliseconds = createdAtMilliseconds
    }
}

struct MeetingTranscriptionUsageMetric: Codable, Hashable {
    let billingUnit: String
    let quantity: Int64

    init(billingUnit: String, quantity: Int64) throws {
        self.billingUnit = try MeetingTranscriptionValidation.normalizedIdentifier(
            billingUnit,
            field: "usage.billingUnit"
        )
        guard quantity >= 0 else { throw MeetingTranscriptionValidationError.invalidEvent("usage.quantity") }
        self.quantity = quantity
    }
}

struct MeetingTranscriptionUsageEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let metrics: [MeetingTranscriptionUsageMetric]
    let pricingSnapshotID: String?

    init(
        context: MeetingTranscriptionEventContext,
        metrics: [MeetingTranscriptionUsageMetric],
        pricingSnapshotID: String? = nil
    ) throws {
        guard !metrics.isEmpty,
              metrics.count <= 64,
              Set(metrics.map(\.billingUnit)).count == metrics.count
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("usage.metrics")
        }
        self.context = context
        self.metrics = metrics
        self.pricingSnapshotID = try pricingSnapshotID.map {
            try MeetingTranscriptionValidation.normalizedIdentifier($0, field: "usage.pricingSnapshotID")
        }
    }
}

struct MeetingTranscriptionRateLimitEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let scope: String
    let limit: Int64?
    let remaining: Int64?
    let resetsAtMilliseconds: Int64?
    let retryAfterMilliseconds: Int64?

    init(
        context: MeetingTranscriptionEventContext,
        scope: String,
        limit: Int64? = nil,
        remaining: Int64? = nil,
        resetsAtMilliseconds: Int64? = nil,
        retryAfterMilliseconds: Int64? = nil
    ) throws {
        self.context = context
        self.scope = try MeetingTranscriptionValidation.normalizedIdentifier(scope, field: "rateLimit.scope")
        if let limit, let remaining, remaining > limit {
            throw MeetingTranscriptionValidationError.invalidEvent("rateLimit")
        }
        guard limit.map({ $0 >= 0 }) ?? true,
              remaining.map({ $0 >= 0 }) ?? true,
              resetsAtMilliseconds.map({ $0 >= 0 }) ?? true,
              retryAfterMilliseconds.map({ $0 >= 0 }) ?? true
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("rateLimit")
        }
        self.limit = limit
        self.remaining = remaining
        self.resetsAtMilliseconds = resetsAtMilliseconds
        self.retryAfterMilliseconds = retryAfterMilliseconds
    }
}

struct MeetingTranscriptionWarningEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let code: String
    let message: String
    let isRecoverable: Bool

    init(context: MeetingTranscriptionEventContext, code: String, message: String, isRecoverable: Bool) throws {
        self.context = context
        self.code = try MeetingTranscriptionValidation.normalizedIdentifier(code, field: "warning.code")
        self.message = try MeetingTranscriptionValidation.normalizedText(
            message,
            field: "warning.message",
            maximumLength: 2000
        )
        self.isRecoverable = isRecoverable
    }
}

enum MeetingTranscriptionSessionState: String, Codable, CaseIterable, Hashable {
    case starting
    case ready
    case draining
    case completed
    case cancelled
}

enum MeetingTranscriptionTrackRuntimeState: String, Codable, CaseIterable, Hashable {
    case starting
    case ready
    case reconnecting
    case rateLimited
    case localFallback
    case draining
    case completed
    case failed
    case cancelled
}

struct MeetingTranscriptionTrackHealthEvent: Codable, Hashable {
    let trackID: UUID
    let providerEpoch: MeetingProviderEpoch
    let state: MeetingTranscriptionTrackRuntimeState
    let updatedAtMilliseconds: Int64
    let code: String?

    init(
        trackID: UUID,
        providerEpoch: MeetingProviderEpoch,
        state: MeetingTranscriptionTrackRuntimeState,
        updatedAtMilliseconds: Int64,
        code: String? = nil
    ) throws {
        guard updatedAtMilliseconds >= 0 else {
            throw MeetingTranscriptionValidationError.invalidEvent("trackHealth.updatedAtMilliseconds")
        }
        self.trackID = trackID
        self.providerEpoch = providerEpoch
        self.state = state
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.code = try code.map {
            try MeetingTranscriptionValidation.normalizedIdentifier($0, field: "trackHealth.code")
        }
    }
}

struct MeetingTranscriptionSessionEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let state: MeetingTranscriptionSessionState
    let providerSessionID: String?

    init(
        context: MeetingTranscriptionEventContext,
        state: MeetingTranscriptionSessionState,
        providerSessionID: String? = nil
    ) throws {
        self.context = context
        self.state = state
        self.providerSessionID = try providerSessionID.map {
            try MeetingTranscriptionValidation.normalizedIdentifier($0, field: "session.providerSessionID")
        }
    }
}

struct MeetingTranscriptionPartialEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let utterance: MeetingTranscriptionUtterance
}

struct MeetingTranscriptionFinalEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let utterance: MeetingTranscriptionUtterance
}

struct MeetingTranscriptionReplacementEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let replacesUtteranceID: UUID
    let replacesRevision: Int
    let utterance: MeetingTranscriptionUtterance

    init(
        context: MeetingTranscriptionEventContext,
        replacesUtteranceID: UUID,
        replacesRevision: Int,
        utterance: MeetingTranscriptionUtterance
    ) throws {
        guard replacesUtteranceID == utterance.id,
              replacesRevision >= 0,
              utterance.revision > replacesRevision
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("replacement")
        }
        self.context = context
        self.replacesUtteranceID = replacesUtteranceID
        self.replacesRevision = replacesRevision
        self.utterance = utterance
    }
}

struct MeetingTranscriptionMetadataAmendmentEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let utteranceID: UUID
    let expectedRevision: Int
    let words: [MeetingNormalizedWord]
    let speaker: MeetingNormalizedSpeaker?

    init(
        context: MeetingTranscriptionEventContext,
        utteranceID: UUID,
        expectedRevision: Int,
        words: [MeetingNormalizedWord],
        speaker: MeetingNormalizedSpeaker?
    ) throws {
        guard expectedRevision >= 0,
              words.count <= 10000,
              Set(words.map(\.id)).count == words.count
        else {
            throw MeetingTranscriptionValidationError.invalidEvent("metadataAmendment")
        }
        self.context = context
        self.utteranceID = utteranceID
        self.expectedRevision = expectedRevision
        self.words = words
        self.speaker = speaker
    }
}

enum MeetingTranscriptionFailureClassification: String, Codable, CaseIterable, Hashable {
    case transient
    case rateLimited
    case authentication
    case authorization
    case invalidRequest
    case unavailable
    case quotaExceeded
    case cancelled
    case permanent
}

struct MeetingTranscriptionFailureEvent: Codable, Hashable {
    let context: MeetingTranscriptionEventContext
    let code: String
    let message: String
    let classification: MeetingTranscriptionFailureClassification
    let retryAfterMilliseconds: Int64?

    init(
        context: MeetingTranscriptionEventContext,
        code: String,
        message: String,
        classification: MeetingTranscriptionFailureClassification,
        retryAfterMilliseconds: Int64? = nil
    ) throws {
        self.context = context
        self.code = try MeetingTranscriptionValidation.normalizedIdentifier(code, field: "failure.code")
        self.message = try MeetingTranscriptionValidation.normalizedText(
            message,
            field: "failure.message",
            maximumLength: 2000
        )
        guard retryAfterMilliseconds.map({ $0 >= 0 }) ?? true else {
            throw MeetingTranscriptionValidationError.invalidEvent("failure.retryAfter")
        }
        self.classification = classification
        self.retryAfterMilliseconds = retryAfterMilliseconds
    }
}

enum MeetingTranscriptionProviderEvent: Codable, Hashable {
    case usage(MeetingTranscriptionUsageEvent)
    case rateLimit(MeetingTranscriptionRateLimitEvent)
    case warning(MeetingTranscriptionWarningEvent)
    case session(MeetingTranscriptionSessionEvent)
    case partial(MeetingTranscriptionPartialEvent)
    case final(MeetingTranscriptionFinalEvent)
    case replacement(MeetingTranscriptionReplacementEvent)
    case metadataAmendment(MeetingTranscriptionMetadataAmendmentEvent)
    case failure(MeetingTranscriptionFailureEvent)

    var context: MeetingTranscriptionEventContext {
        switch self {
        case let .usage(event): event.context
        case let .rateLimit(event): event.context
        case let .warning(event): event.context
        case let .session(event): event.context
        case let .partial(event): event.context
        case let .final(event): event.context
        case let .replacement(event): event.context
        case let .metadataAmendment(event): event.context
        case let .failure(event): event.context
        }
    }
}
