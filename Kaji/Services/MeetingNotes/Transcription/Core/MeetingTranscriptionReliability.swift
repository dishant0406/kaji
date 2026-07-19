import CryptoKit
import Foundation

enum MeetingTranscriptionRetryClassification: String, Codable, CaseIterable, Hashable {
    case transient
    case rateLimited
    case unavailable
    case authentication
    case authorization
    case invalidRequest
    case quotaExceeded
    case cancelled
    case permanent
}

enum MeetingTranscriptionRetryDecision: Equatable {
    case retry(delayMilliseconds: ClosedRange<Int64>)
    case stop
}

struct MeetingTranscriptionRetryPolicy: Codable, Hashable {
    let maximumAttempts: Int
    let baseDelayMilliseconds: Int64
    let maximumDelayMilliseconds: Int64
    let jitterBasisPoints: Int
    let retryableClassifications: Set<MeetingTranscriptionRetryClassification>

    init(
        maximumAttempts: Int,
        baseDelayMilliseconds: Int64,
        maximumDelayMilliseconds: Int64,
        jitterBasisPoints: Int = 0,
        retryableClassifications: Set<MeetingTranscriptionRetryClassification>
    ) throws {
        guard 1 ... 20 ~= maximumAttempts,
              baseDelayMilliseconds >= 0,
              maximumDelayMilliseconds >= baseDelayMilliseconds,
              maximumDelayMilliseconds <= 3_600_000,
              0 ... 10000 ~= jitterBasisPoints
        else {
            throw MeetingTranscriptionValidationError.invalidValue("retryPolicy")
        }
        self.maximumAttempts = maximumAttempts
        self.baseDelayMilliseconds = baseDelayMilliseconds
        self.maximumDelayMilliseconds = maximumDelayMilliseconds
        self.jitterBasisPoints = jitterBasisPoints
        self.retryableClassifications = retryableClassifications
    }

    private enum CodingKeys: String, CodingKey {
        case maximumAttempts
        case baseDelayMilliseconds
        case maximumDelayMilliseconds
        case jitterBasisPoints
        case retryableClassifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            maximumAttempts: container.decode(Int.self, forKey: .maximumAttempts),
            baseDelayMilliseconds: container.decode(Int64.self, forKey: .baseDelayMilliseconds),
            maximumDelayMilliseconds: container.decode(Int64.self, forKey: .maximumDelayMilliseconds),
            jitterBasisPoints: container.decode(Int.self, forKey: .jitterBasisPoints),
            retryableClassifications: container.decode(
                Set<MeetingTranscriptionRetryClassification>.self,
                forKey: .retryableClassifications
            )
        )
    }

    func decision(
        classification: MeetingTranscriptionRetryClassification,
        attempt: Int,
        retryAfterMilliseconds: Int64? = nil
    ) -> MeetingTranscriptionRetryDecision {
        guard attempt >= 1,
              attempt < maximumAttempts,
              retryableClassifications.contains(classification)
        else {
            return .stop
        }
        let exponent = min(attempt - 1, 30)
        let multiplier = Int64(1) << Int64(exponent)
        let product = baseDelayMilliseconds.multipliedReportingOverflow(by: multiplier)
        let exponentialDelay = product.overflow ? maximumDelayMilliseconds : product.partialValue
        let requiredDelay = max(exponentialDelay, retryAfterMilliseconds ?? 0)
        let boundedDelay = min(requiredDelay, maximumDelayMilliseconds)
        let jitter = boundedDelay.multipliedReportingOverflow(by: Int64(jitterBasisPoints))
        let jitterAmount = jitter.overflow ? boundedDelay : jitter.partialValue / 10000
        return .retry(
            delayMilliseconds: max(0, boundedDelay - jitterAmount) ... min(
                maximumDelayMilliseconds,
                boundedDelay + jitterAmount
            )
        )
    }
}

struct MeetingTranscriptionOperationIdentity: Codable, Hashable {
    let operationID: UUID
    let sessionID: UUID
    let trackID: UUID
    let sampleRange: MeetingCanonicalSampleRange
    let providerEpoch: MeetingProviderEpoch
    let source: MeetingTranscriptionSource
    let encoding: MeetingTranscriptionAudioEncoding
    let channelCount: Int
    let payloadSHA256: Data
    let isEndOfStream: Bool

    init(packet: MeetingNormalizedAudioPacket) {
        operationID = packet.operationID
        sessionID = packet.sessionID
        trackID = packet.trackID
        sampleRange = packet.sampleRange
        providerEpoch = packet.providerEpoch
        source = packet.source
        encoding = packet.encoding
        channelCount = packet.channelCount
        payloadSHA256 = Data(SHA256.hash(data: packet.bytes))
        isEndOfStream = packet.isEndOfStream
    }
}

enum MeetingTranscriptionOperationState: String, Codable, CaseIterable, Hashable {
    case pending
    case acknowledged
    case completed
    case failed
}

enum MeetingTranscriptionOperationLedgerResult: Equatable {
    case inserted
    case duplicate(MeetingTranscriptionOperationState)
}

enum MeetingTranscriptionOperationLedgerError: Error, Equatable {
    case identityCollision(UUID)
    case operationNotFound(UUID)
    case invalidTransition
    case capacityExceeded
}

actor MeetingTranscriptionOperationLedger {
    struct Entry: Codable, Hashable {
        let identity: MeetingTranscriptionOperationIdentity
        var state: MeetingTranscriptionOperationState
    }

    private let maximumEntries: Int
    private var entries: [UUID: Entry] = [:]

    init(maximumEntries: Int = 100_000) throws {
        guard 1 ... 1_000_000 ~= maximumEntries else {
            throw MeetingTranscriptionValidationError.invalidValue("operationLedger.maximumEntries")
        }
        self.maximumEntries = maximumEntries
    }

    func record(_ identity: MeetingTranscriptionOperationIdentity) throws -> MeetingTranscriptionOperationLedgerResult {
        if let entry = entries[identity.operationID] {
            guard entry.identity == identity else {
                throw MeetingTranscriptionOperationLedgerError.identityCollision(identity.operationID)
            }
            return .duplicate(entry.state)
        }
        guard entries.count < maximumEntries else {
            throw MeetingTranscriptionOperationLedgerError.capacityExceeded
        }
        entries[identity.operationID] = Entry(identity: identity, state: .pending)
        return .inserted
    }

    func transition(operationID: UUID, to state: MeetingTranscriptionOperationState) throws {
        guard var entry = entries[operationID] else {
            throw MeetingTranscriptionOperationLedgerError.operationNotFound(operationID)
        }
        guard Self.canTransition(from: entry.state, to: state) else {
            throw MeetingTranscriptionOperationLedgerError.invalidTransition
        }
        entry.state = state
        entries[operationID] = entry
    }

    func entry(operationID: UUID) -> Entry? {
        entries[operationID]
    }

    private static func canTransition(
        from current: MeetingTranscriptionOperationState,
        to next: MeetingTranscriptionOperationState
    ) -> Bool {
        switch (current, next) {
        case (.pending, .acknowledged),
             (.pending, .failed),
             (.acknowledged, .completed),
             (.acknowledged, .failed):
            true
        default:
            false
        }
    }
}

struct MeetingProviderEpochCutover: Codable, Hashable {
    let trackID: UUID
    let previousEpoch: MeetingProviderEpoch
    let nextEpoch: MeetingProviderEpoch
    let cutoverFrame: Int64

    init(
        trackID: UUID,
        previousEpoch: MeetingProviderEpoch,
        nextEpoch: MeetingProviderEpoch,
        cutoverFrame: Int64
    ) throws {
        guard nextEpoch > previousEpoch, cutoverFrame >= 0 else {
            throw MeetingTranscriptionValidationError.invalidValue("providerEpochCutover")
        }
        self.trackID = trackID
        self.previousEpoch = previousEpoch
        self.nextEpoch = nextEpoch
        self.cutoverFrame = cutoverFrame
    }

    func accepts(epoch: MeetingProviderEpoch, sampleRange: MeetingCanonicalSampleRange) -> Bool {
        if epoch == previousEpoch {
            return sampleRange.endFrame <= cutoverFrame
        }
        if epoch == nextEpoch {
            return sampleRange.startFrame >= cutoverFrame
        }
        return false
    }
}

actor MeetingProviderEpochCoordinator {
    private var activeEpochs: [UUID: MeetingProviderEpoch] = [:]
    private var cutovers: [UUID: MeetingProviderEpochCutover] = [:]

    func activate(_ epoch: MeetingProviderEpoch, trackID: UUID) throws {
        if let active = activeEpochs[trackID], epoch < active {
            throw MeetingTranscriptionValidationError.invalidValue("providerEpoch")
        }
        activeEpochs[trackID] = epoch
    }

    func cutover(_ cutover: MeetingProviderEpochCutover) throws {
        guard activeEpochs[cutover.trackID] == cutover.previousEpoch else {
            throw MeetingTranscriptionValidationError.invalidValue("providerEpochCutover.previousEpoch")
        }
        activeEpochs[cutover.trackID] = cutover.nextEpoch
        cutovers[cutover.trackID] = cutover
    }

    func accepts(
        trackID: UUID,
        epoch: MeetingProviderEpoch,
        sampleRange: MeetingCanonicalSampleRange
    ) -> Bool {
        if let cutover = cutovers[trackID],
           epoch == cutover.previousEpoch || epoch == cutover.nextEpoch
        {
            return cutover.accepts(epoch: epoch, sampleRange: sampleRange)
        }
        return activeEpochs[trackID].map { epoch == $0 } ?? true
    }
}
