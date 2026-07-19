import Foundation

enum MeetingSynthesisSchedulerError: Error, Equatable {
    case invalidInput
}

struct MeetingSynthesisSchedule: Equatable {
    let sessionID: UUID
    let dueAtMilliseconds: Int64
    let transcriptRevision: Int
    let coalescedRequestCount: Int
}

enum MeetingSynthesisScheduleResult: Equatable {
    case scheduled(MeetingSynthesisSchedule)
    case coalesced(MeetingSynthesisSchedule)
}

actor MeetingSynthesisScheduler {
    private let intervalMilliseconds: Int64
    private var pending: [UUID: MeetingSynthesisSchedule] = [:]
    private var inFlight: [UUID: MeetingSynthesisSchedule] = [:]

    init(intervalMinutes: Int) throws {
        guard (1 ... 30).contains(intervalMinutes) else { throw MeetingSynthesisSchedulerError.invalidInput }
        intervalMilliseconds = Int64(intervalMinutes) * 60000
    }

    func submit(
        sessionID: UUID,
        transcriptRevision: Int,
        nowMilliseconds: Int64
    ) throws -> MeetingSynthesisScheduleResult {
        guard transcriptRevision >= 0, nowMilliseconds >= 0 else { throw MeetingSynthesisSchedulerError.invalidInput }
        if let existing = pending[sessionID] {
            let updated = MeetingSynthesisSchedule(
                sessionID: sessionID,
                dueAtMilliseconds: existing.dueAtMilliseconds,
                transcriptRevision: max(existing.transcriptRevision, transcriptRevision),
                coalescedRequestCount: existing.coalescedRequestCount + 1
            )
            pending[sessionID] = updated
            return .coalesced(updated)
        }
        guard nowMilliseconds <= Int64.max - intervalMilliseconds else {
            throw MeetingSynthesisSchedulerError.invalidInput
        }
        let schedule = MeetingSynthesisSchedule(
            sessionID: sessionID,
            dueAtMilliseconds: nowMilliseconds + intervalMilliseconds,
            transcriptRevision: transcriptRevision,
            coalescedRequestCount: 1
        )
        pending[sessionID] = schedule
        return inFlight[sessionID] == nil ? .scheduled(schedule) : .coalesced(schedule)
    }

    func takeDue(atMilliseconds: Int64) throws -> [MeetingSynthesisSchedule] {
        guard atMilliseconds >= 0 else { throw MeetingSynthesisSchedulerError.invalidInput }
        let due = pending.values
            .filter { $0.dueAtMilliseconds <= atMilliseconds && inFlight[$0.sessionID] == nil }
            .sorted {
                if $0.dueAtMilliseconds == $1.dueAtMilliseconds {
                    return $0.sessionID.uuidString < $1.sessionID.uuidString
                }
                return $0.dueAtMilliseconds < $1.dueAtMilliseconds
            }
        for schedule in due {
            pending.removeValue(forKey: schedule.sessionID)
            inFlight[schedule.sessionID] = schedule
        }
        return due
    }

    func complete(sessionID: UUID, succeeded: Bool, nowMilliseconds: Int64) throws {
        guard nowMilliseconds >= 0 else { throw MeetingSynthesisSchedulerError.invalidInput }
        guard let completed = inFlight[sessionID] else { return }
        if !succeeded, pending[sessionID] == nil, nowMilliseconds > Int64.max - intervalMilliseconds {
            throw MeetingSynthesisSchedulerError.invalidInput
        }
        inFlight.removeValue(forKey: sessionID)
        guard !succeeded, pending[sessionID] == nil else { return }
        pending[sessionID] = MeetingSynthesisSchedule(
            sessionID: sessionID,
            dueAtMilliseconds: nowMilliseconds + intervalMilliseconds,
            transcriptRevision: completed.transcriptRevision,
            coalescedRequestCount: completed.coalescedRequestCount
        )
    }

    func cancel(sessionID: UUID) {
        pending.removeValue(forKey: sessionID)
        inFlight.removeValue(forKey: sessionID)
    }

    func pendingSchedule(sessionID: UUID) -> MeetingSynthesisSchedule? {
        pending[sessionID]
    }
}
