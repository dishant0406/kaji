import Foundation
import Testing

@testable import Kaji

@Suite("Deepgram provider failures")
struct DeepgramProviderFailureTests {
    @Test(
        "handshake status classifications are stable",
        arguments: [
            (401, MeetingTranscriptionFailureClassification.authentication),
            (429, MeetingTranscriptionFailureClassification.rateLimited),
            (503, MeetingTranscriptionFailureClassification.unavailable)
        ]
    )
    func handshakeClassifications(
        statusCode: Int,
        expected: MeetingTranscriptionFailureClassification
    ) async throws {
        let headers = statusCode == 429
            ? ["Retry-After": "2", "X-RateLimit-Limit": "10", "X-RateLimit-Remaining": "0"]
            : [:]
        let metadata = try DeepgramWebSocketResponseMetadata(statusCode: statusCode, headers: headers)
        let transport = FakeDeepgramTransport(responseMetadata: metadata)
        let provider = try deepgramProvider(transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)

        await #expect(throws: DeepgramMeetingTranscriptionError.providerRejected(expected)) {
            try await session.start()
        }
        let events = try await collector.value
        let failure = try #require(events.compactMap(deepgramFailure).last)
        #expect(failure.classification == expected)
        if statusCode == 429 {
            try verifyRateLimit(events: events, failure: failure)
        }
    }

    @Test("warnings and provider errors are sanitized and classified")
    func warningAndErrorEvents() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        let warningPayload = "{\"type\":\"Warning\",\"warn_code\":\"LOW CONFIDENCE\"," +
            "\"warn_msg\":\"secret transcript\"}"
        let errorPayload = "{\"type\":\"Error\",\"err_code\":\"TOO_MANY_REQUESTS\"," +
            "\"err_msg\":\"secret transcript\",\"status_code\":429,\"retry_after\":1.5}"
        await transport.emit(.message(.text(warningPayload)))
        await transport.emit(.message(.text(errorPayload)))
        let events = try await collector.value
        let warning = try #require(events.compactMap(deepgramWarning).last)
        let failure = try #require(events.compactMap(deepgramFailure).last)

        #expect(warning.code == "low-confidence")
        #expect(warning.message == "Deepgram reported a recoverable warning.")
        #expect(failure.classification == .rateLimited)
        #expect(failure.retryAfterMilliseconds == 1500)
        #expect(!failure.message.contains("secret transcript"))
    }

    @Test("cancellation is terminal and sends no drain controls")
    func cancellation() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        await session.cancel()
        await session.cancel()
        let events = try await collector.value

        #expect(await transport.cancelCallCount() == 1)
        #expect(await transport.sentMessages().isEmpty)
        #expect(events.compactMap(deepgramSessionState).last == .cancelled)
    }

    @Test("provider rate limit events are normalized")
    func rateLimitEvent() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        let payload = "{\"type\":\"RateLimit\",\"scope\":\"project_concurrency\"," +
            "\"limit\":20,\"remaining\":3,\"reset_at\":5000,\"retry_after_ms\":250}"
        await transport.emit(.message(.text(payload)))
        try await Task.sleep(for: .milliseconds(20))
        await session.cancel()
        let event = try #require(try await collector.value.compactMap(deepgramRateLimit).last)

        #expect(event.scope == "project-concurrency")
        #expect(event.limit == 20)
        #expect(event.remaining == 3)
        #expect(event.resetsAtMilliseconds == 5000)
        #expect(event.retryAfterMilliseconds == 250)
    }

    private func verifyRateLimit(
        events: [MeetingTranscriptionProviderEvent],
        failure: MeetingTranscriptionFailureEvent
    ) throws {
        let rateLimit = try #require(events.compactMap(deepgramRateLimit).last)
        #expect(rateLimit.limit == 10)
        #expect(rateLimit.remaining == 0)
        #expect(rateLimit.retryAfterMilliseconds == 2000)
        #expect(failure.retryAfterMilliseconds == 2000)
    }
}
