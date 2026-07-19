import Foundation

@testable import Kaji

enum MeetingNotesTestFixtures {
    static let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let trackID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let segmentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    static func session(
        id: UUID = UUID(),
        title: String = "Weekly planning",
        createdAtMilliseconds: Int64 = 1_000,
        phase: MeetingLifecyclePhase = .ready,
        updatedAtMilliseconds: Int64? = nil,
        isPinned: Bool = false
    ) throws -> MeetingSession {
        var session = try MeetingSession(
            id: id,
            title: title,
            projectIDs: [projectID],
            createdAtMilliseconds: createdAtMilliseconds,
            isPinned: isPinned
        )
        if phase != .ready {
            try session.transition(to: .recording, atMilliseconds: createdAtMilliseconds + 1)
        }
        if phase == .paused {
            try session.transition(to: .paused, atMilliseconds: createdAtMilliseconds + 2)
        }
        if phase == .completed {
            try session.transition(to: .completed, atMilliseconds: createdAtMilliseconds + 2)
        }
        if phase == .interrupted {
            try session.transition(
                to: .interrupted,
                atMilliseconds: createdAtMilliseconds + 2,
                interruptionReason: "Test interruption"
            )
        }
        if let updatedAtMilliseconds, updatedAtMilliseconds > session.updatedAtMilliseconds {
            try session.touch(atMilliseconds: updatedAtMilliseconds)
        }
        return session
    }

    static func track() -> MeetingSourceTrack {
        MeetingSourceTrack(
            id: trackID,
            kind: .microphone,
            displayName: "Built-in microphone",
            sampleRateHertz: 16_000,
            channelCount: 1,
            startedAtMilliseconds: 1_001
        )
    }

    static func segment() throws -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(
            id: segmentID,
            trackID: trackID,
            sampleRange: try MeetingSampleRange(startFrame: 0, endFrame: 16_000, sampleRateHertz: 16_000),
            startMilliseconds: 1_001,
            endMilliseconds: 2_001,
            text: "Ship the desktop release on Friday.",
            speakerLabel: "Alex",
            isFinal: true,
            createdAtMilliseconds: 2_001
        )
    }

    static func document(
        id: UUID = UUID(),
        phase: MeetingLifecyclePhase = .ready,
        updatedAtMilliseconds: Int64? = nil,
        isPinned: Bool = false
    ) throws -> MeetingSessionDocument {
        let session = try session(
            id: id,
            phase: phase,
            updatedAtMilliseconds: updatedAtMilliseconds,
            isPinned: isPinned
        )
        return MeetingSessionDocument(session: session)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingNotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
