import Testing

@testable import Kaji

@MainActor
@Suite("Meeting audio capture abstraction")
struct MeetingAudioCaptureSessionTests {
    @Test("hardware capture lifecycle can be replaced by a deterministic session")
    func mockLifecycle() async throws {
        let session: any MeetingAudioCaptureSession = MeetingAudioCaptureSessionMock()

        try await session.start()
        #expect(session.isCapturing)
        try await session.stop()
        #expect(!session.isCapturing)
    }
}

@MainActor
private final class MeetingAudioCaptureSessionMock: MeetingAudioCaptureSession {
    private(set) var isCapturing = false

    func start() async throws {
        guard !isCapturing else { throw MeetingAudioError.captureAlreadyRunning }
        isCapturing = true
    }

    func stop() async throws {
        guard isCapturing else { throw MeetingAudioError.captureNotRunning }
        isCapturing = false
    }
}
