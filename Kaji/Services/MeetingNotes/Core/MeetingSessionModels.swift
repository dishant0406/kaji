import Foundation

enum MeetingDomainError: Error, Equatable {
    case invalidTimestamp
    case invalidSampleRange
    case invalidLifecycleTransition
    case invalidLifecycle
    case invalidSession
    case invalidTrack
    case invalidAudioChunk
    case invalidTranscriptSegment
    case invalidDocument
}

enum MeetingLifecyclePhase: String, Codable, CaseIterable {
    case ready
    case recording
    case paused
    case completed
    case interrupted

    var isActive: Bool {
        self == .recording || self == .paused
    }

    var isTerminal: Bool {
        self == .completed || self == .interrupted
    }
}

struct MeetingSessionLifecycle: Codable, Equatable {
    private(set) var phase: MeetingLifecyclePhase
    let createdAtMilliseconds: Int64
    private(set) var startedAtMilliseconds: Int64?
    private(set) var endedAtMilliseconds: Int64?
    private(set) var interruptionReason: String?

    init(createdAtMilliseconds: Int64) throws {
        guard createdAtMilliseconds >= 0 else { throw MeetingDomainError.invalidTimestamp }
        phase = .ready
        self.createdAtMilliseconds = createdAtMilliseconds
    }

    mutating func transition(
        to nextPhase: MeetingLifecyclePhase,
        atMilliseconds: Int64,
        interruptionReason: String? = nil
    ) throws {
        guard atMilliseconds >= createdAtMilliseconds else { throw MeetingDomainError.invalidTimestamp }
        guard Self.canTransition(from: phase, to: nextPhase) else {
            throw MeetingDomainError.invalidLifecycleTransition
        }
        var updated = self
        if nextPhase == .interrupted {
            guard let interruptionReason,
                  !interruptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  interruptionReason.count <= 500
            else {
                throw MeetingDomainError.invalidLifecycle
            }
            updated.interruptionReason = interruptionReason
        } else {
            guard interruptionReason == nil else { throw MeetingDomainError.invalidLifecycle }
            updated.interruptionReason = nil
        }
        if nextPhase == .recording, updated.startedAtMilliseconds == nil {
            updated.startedAtMilliseconds = atMilliseconds
        }
        if nextPhase.isTerminal {
            updated.endedAtMilliseconds = atMilliseconds
        }
        updated.phase = nextPhase
        try updated.validate()
        self = updated
    }

    func validate() throws {
        guard createdAtMilliseconds >= 0 else { throw MeetingDomainError.invalidLifecycle }
        if let startedAtMilliseconds {
            guard startedAtMilliseconds >= createdAtMilliseconds else { throw MeetingDomainError.invalidLifecycle }
        }
        if phase == .ready {
            guard startedAtMilliseconds == nil,
                  endedAtMilliseconds == nil,
                  interruptionReason == nil
            else {
                throw MeetingDomainError.invalidLifecycle
            }
            return
        }
        guard startedAtMilliseconds != nil else { throw MeetingDomainError.invalidLifecycle }
        if phase.isActive {
            guard endedAtMilliseconds == nil, interruptionReason == nil else {
                throw MeetingDomainError.invalidLifecycle
            }
            return
        }
        guard let endedAtMilliseconds,
              let startedAtMilliseconds,
              endedAtMilliseconds >= startedAtMilliseconds
        else {
            throw MeetingDomainError.invalidLifecycle
        }
        if phase == .completed {
            guard interruptionReason == nil else { throw MeetingDomainError.invalidLifecycle }
            return
        }
        guard let interruptionReason,
              !interruptionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              interruptionReason.count <= 500
        else {
            throw MeetingDomainError.invalidLifecycle
        }
    }

    private static func canTransition(from current: MeetingLifecyclePhase, to next: MeetingLifecyclePhase) -> Bool {
        switch (current, next) {
        case (.ready, .recording),
             (.recording, .paused),
             (.recording, .completed),
             (.recording, .interrupted),
             (.paused, .recording),
             (.paused, .completed),
             (.paused, .interrupted):
            true
        default:
            false
        }
    }
}

enum MeetingSourceKind: String, Codable, CaseIterable {
    case microphone
    case systemAudio
    case importedAudio
}

enum MeetingProjectContextScope: String, Codable, CaseIterable {
    case active
    case all
}

struct MeetingSourceTrack: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: MeetingSourceKind
    let displayName: String
    let sampleRateHertz: Int
    let channelCount: Int
    let startedAtMilliseconds: Int64
}

struct MeetingSampleRange: Codable, Hashable {
    let startFrame: Int64
    let endFrame: Int64
    let sampleRateHertz: Int

    init(startFrame: Int64, endFrame: Int64, sampleRateHertz: Int) throws {
        guard startFrame >= 0, endFrame > startFrame, sampleRateHertz > 0 else {
            throw MeetingDomainError.invalidSampleRange
        }
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.sampleRateHertz = sampleRateHertz
    }

    var frameCount: Int64 {
        endFrame - startFrame
    }
}

enum MeetingAudioStorageState: String, Codable, CaseIterable {
    case notStored
    case stored
    case deleted
}

enum MeetingAudioEncoding: String, Codable, CaseIterable {
    case caf
    case wav
    case pcm

    var fileExtension: String {
        rawValue
    }
}

struct MeetingAudioChunkMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    let trackID: UUID
    let sampleRange: MeetingSampleRange
    let capturedAtMilliseconds: Int64
    let byteCount: Int64
    let encoding: MeetingAudioEncoding
    var storageState: MeetingAudioStorageState
}

struct MeetingTranscriptSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let trackID: UUID
    let sampleRange: MeetingSampleRange
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let text: String
    let speakerLabel: String?
    let isFinal: Bool
    let createdAtMilliseconds: Int64
}

struct MeetingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var projectIDs: [UUID]
    var lifecycle: MeetingSessionLifecycle
    var updatedAtMilliseconds: Int64
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        projectIDs: [UUID] = [],
        createdAtMilliseconds: Int64,
        isPinned: Bool = false
    ) throws {
        let lifecycle = try MeetingSessionLifecycle(createdAtMilliseconds: createdAtMilliseconds)
        self.id = id
        self.title = title
        self.projectIDs = projectIDs
        self.lifecycle = lifecycle
        updatedAtMilliseconds = createdAtMilliseconds
        self.isPinned = isPinned
        try validate()
    }

    mutating func transition(
        to phase: MeetingLifecyclePhase,
        atMilliseconds: Int64,
        interruptionReason: String? = nil
    ) throws {
        guard atMilliseconds >= updatedAtMilliseconds else { throw MeetingDomainError.invalidTimestamp }
        try lifecycle.transition(
            to: phase,
            atMilliseconds: atMilliseconds,
            interruptionReason: interruptionReason
        )
        updatedAtMilliseconds = atMilliseconds
    }

    mutating func touch(atMilliseconds: Int64) throws {
        guard atMilliseconds >= updatedAtMilliseconds else { throw MeetingDomainError.invalidTimestamp }
        updatedAtMilliseconds = atMilliseconds
    }

    func validate() throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              title.count <= 200,
              Set(projectIDs).count == projectIDs.count,
              projectIDs.count <= 20,
              updatedAtMilliseconds >= lifecycle.createdAtMilliseconds
        else {
            throw MeetingDomainError.invalidSession
        }
        try lifecycle.validate()
        if let endedAtMilliseconds = lifecycle.endedAtMilliseconds {
            guard updatedAtMilliseconds >= endedAtMilliseconds else { throw MeetingDomainError.invalidSession }
        }
    }
}
