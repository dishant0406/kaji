import Foundation
import Testing

@testable import Kaji

@Suite("Meeting project context and scheduling")
struct MeetingProjectContextAndSchedulerTests {
    @Test("project context enforces allowlist, path safety, counts, and character budget")
    func contextBounds() {
        let allowed = MeetingNotesTestFixtures.projectID
        let denied = UUID()
        let limits = MeetingProjectContextLimits(
            maximumProjects: 1,
            maximumFilesPerProject: 2,
            maximumTotalCharacters: 30,
            maximumNameLength: 10,
            maximumSummaryLength: 10,
            maximumRelativePathLength: 10
        )
        let context = MeetingProjectContextBuilder(limits: limits).build(
            from: [
                MeetingProjectContextInput(
                    projectID: denied,
                    name: "Denied",
                    summary: "Denied",
                    recentRelativeFilePaths: ["secret.txt"]
                ),
                MeetingProjectContextInput(
                    projectID: allowed,
                    name: "A very long project name",
                    summary: "A deliberately long summary",
                    recentRelativeFilePaths: ["/absolute", "a/../b", "Sources/A.swift", "B.swift", "C.swift"]
                ),
            ],
            allowedProjectIDs: [allowed]
        )

        #expect(context.projects.count == 1)
        #expect(context.projects[0].projectID == allowed)
        #expect(context.projects[0].name.count <= 10)
        #expect(context.projects[0].recentRelativeFilePaths.count <= 2)
        #expect(!context.projects[0].recentRelativeFilePaths.contains("/absolute"))
        #expect(!context.projects[0].recentRelativeFilePaths.contains("a/../b"))
        #expect(context.totalCharacterCount <= 30)
    }

    @Test("scheduler coalesces without extending deadline and serializes in-flight work")
    func scheduling() async throws {
        let sessionID = UUID()
        let scheduler = try MeetingSynthesisScheduler(intervalMinutes: 1)
        let first = try await scheduler.submit(
            sessionID: sessionID,
            transcriptRevision: 1,
            nowMilliseconds: 0
        )
        #expect(first == .scheduled(MeetingSynthesisSchedule(
            sessionID: sessionID,
            dueAtMilliseconds: 60_000,
            transcriptRevision: 1,
            coalescedRequestCount: 1
        )))
        let second = try await scheduler.submit(
            sessionID: sessionID,
            transcriptRevision: 3,
            nowMilliseconds: 10_000
        )
        #expect(second == .coalesced(MeetingSynthesisSchedule(
            sessionID: sessionID,
            dueAtMilliseconds: 60_000,
            transcriptRevision: 3,
            coalescedRequestCount: 2
        )))
        #expect(try await scheduler.takeDue(atMilliseconds: 59_999).isEmpty)
        let due = try await scheduler.takeDue(atMilliseconds: 60_000)
        #expect(due.count == 1)
        #expect(due[0].transcriptRevision == 3)
        _ = try await scheduler.submit(
            sessionID: sessionID,
            transcriptRevision: 4,
            nowMilliseconds: 60_001
        )
        #expect(try await scheduler.takeDue(atMilliseconds: 120_001).isEmpty)
        try await scheduler.complete(sessionID: sessionID, succeeded: true, nowMilliseconds: 60_002)
        let next = try await scheduler.takeDue(atMilliseconds: 120_001)
        #expect(next.map(\.transcriptRevision) == [4])
        try await scheduler.complete(sessionID: sessionID, succeeded: false, nowMilliseconds: 120_002)
        #expect(await scheduler.pendingSchedule(sessionID: sessionID)?.dueAtMilliseconds == 180_002)
    }
}
