import Foundation
import Testing

@testable import Kaji

@Suite("OpenAI realtime meeting transcription")
struct OpenAIRealtimeTranscriptionSessionTests {
    @Test("session update is strict 24 kHz manual commit without prompt or diarization")
    func sessionUpdateAndAudio() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let route = try provider.route(model: .realtimeWhisper, languageCode: "en")
        let session = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        try await session.start()
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(frameCount: 240, sampleRateHertz: 24_000)
        try await session.submit(packet)
        try await OpenAIMeetingTranscriptionTestFixtures.waitForMessages(3, transport: webSocket)
        let messages = await webSocket.capturedMessages().compactMap { message -> [String: Any]? in
            guard case let .text(text) = message,
                  let data = text.data(using: .utf8)
            else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let update = try #require(messages.first)
        let updateText = try #require(String(data: JSONSerialization.data(withJSONObject: update), encoding: .utf8))
        #expect(update["type"] as? String == "session.update")
        #expect(updateText.contains("gpt-realtime-whisper"))
        #expect(updateText.contains("24000"))
        #expect(updateText.contains("turn_detection"))
        #expect(!updateText.contains("prompt"))
        #expect(!updateText.contains("Kaji"))
        #expect(messages.dropFirst().compactMap { $0["type"] as? String } == [
            "input_audio_buffer.append", "input_audio_buffer.commit",
        ])
        let request = try #require(await webSocket.capturedRequests().first)
        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/realtime?intent=transcription")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(OpenAIMeetingTranscriptionTestFixtures.token)")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.value(forHTTPHeaderField: "Pragma") == "no-cache")
        #expect(await webSocket.pings() >= 1)
        await session.cancel()
    }

    @Test("documented and future benign lifecycle events are ignored")
    func benignLifecycleEvents() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }
        try await session.start()
        for event in [
            #"{"type":"conversation.created","conversation":{"id":"conv_1"}}"#,
            #"{"type":"conversation.item.created","item":{"id":"item_1"}}"#,
            #"{"type":"input_audio_buffer.speech_started","audio_start_ms":10}"#,
            #"{"type":"input_audio_buffer.speech_stopped","audio_end_ms":20}"#,
            #"{"type":"input_audio_buffer.cleared"}"#,
            #"{"type":"session.updated","session":{"id":"session_1"}}"#,
            #"{"type":"provider.future.lifecycle","bounded":true}"#,
        ] {
            await webSocket.pushText(event)
        }
        try await Task.sleep(for: .milliseconds(30))
        await session.cancel()
        let events = try await collector.value

        #expect(!events.contains { if case .failure = $0 { true } else { false } })
        #expect(events.contains { event in
            guard case let .session(value) = event else { return false }
            return value.state == .cancelled
        })
    }

    @Test("default conversion seam rejects canonical 16 kHz packets")
    func conversionSeam() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 16_000)
        )
        try await session.start()
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(sampleRateHertz: 16_000)
        await #expect(throws: OpenAIMeetingTranscriptionError.invalidPacket) {
            try await session.submit(packet)
        }
        await session.cancel()
    }

    @Test("item ids correlate out of order finals to stable operation ranges")
    func outOfOrderCompletion() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let route = try provider.route(model: .realtimeWhisper)
        let session = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = try OpenAIMeetingTranscriptionTestFixtures.packet(
            operationID: firstID,
            startFrame: 0,
            frameCount: 240,
            sampleRateHertz: 24_000
        )
        let second = try OpenAIMeetingTranscriptionTestFixtures.packet(
            operationID: secondID,
            startFrame: 240,
            frameCount: 240,
            sampleRateHertz: 24_000
        )
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }
        try await session.start()
        try await session.submit(first)
        try await session.submit(second)
        try await webSocket.push(["type": "input_audio_buffer.committed", "item_id": "item_1"])
        try await webSocket.push(["type": "input_audio_buffer.committed", "item_id": "item_2"])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item_2",
            "content_index": 0,
            "transcript": "second",
        ])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item_1",
            "content_index": 0,
            "transcript": "first",
        ])
        try await Task.sleep(for: .milliseconds(30))
        try await session.finish()
        let finals = try await collector.value.compactMap { event -> MeetingTranscriptionFinalEvent? in
            guard case let .final(value) = event else { return nil }
            return value
        }
        #expect(finals.map(\.context.operationID) == [secondID, firstID])
        #expect(finals.map(\.utterance.text) == ["second", "first"])
        #expect(finals.map(\.utterance.sampleRange) == [second.sampleRange, first.sampleRange])
        #expect(finals[1].utterance.id == OpenAIStableIdentity.uuid(operationID: firstID, component: 0))
        #expect(await webSocket.closes().map(\.0) == [1000])
    }

    @Test("empty completed transcripts retire committed items without failing the session")
    func emptyCompletion() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }

        try await session.start()
        try await session.submit(OpenAIMeetingTranscriptionTestFixtures.packet(sampleRateHertz: 24_000))
        try await webSocket.push(["type": "input_audio_buffer.committed", "item_id": "empty_item"])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "empty_item",
            "content_index": 0,
            "transcript": "",
        ])
        try await Task.sleep(for: .milliseconds(20))
        try await session.finish()
        let events = try await collector.value

        #expect(!events.contains { if case .failure = $0 { true } else { false } })
        #expect(!events.contains { if case .final = $0 { true } else { false } })
    }

    @Test("deltas and final revisions preserve identity and optional logprob confidence")
    func deltasFinalsAndLogprobs() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket, logprobs: true)
        let route = try provider.route(model: .realtimeWhisper, languageCode: "en")
        let session = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(sampleRateHertz: 24_000)
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }
        try await session.start()
        try await session.submit(packet)
        try await webSocket.push(["type": "input_audio_buffer.committed", "item_id": "item_delta"])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "item_delta",
            "content_index": 0,
            "delta": "hel",
            "logprobs": [["token": "hel", "logprob": -0.2, "bytes": [104, 101, 108]]],
        ])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "item_delta",
            "content_index": 0,
            "delta": "lo",
            "logprobs": [-0.1],
        ])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item_delta",
            "content_index": 0,
            "transcript": "hello",
        ])
        try await Task.sleep(for: .milliseconds(30))
        try await session.finish()
        let events = try await collector.value
        let partials = events.compactMap { event -> MeetingTranscriptionPartialEvent? in
            guard case let .partial(value) = event else { return nil }
            return value
        }
        let final = try #require(events.compactMap { event -> MeetingTranscriptionFinalEvent? in
            guard case let .final(value) = event else { return nil }
            return value
        }.first)
        #expect(partials.map(\.utterance.revision) == [0, 1])
        #expect(partials.map(\.utterance.text) == ["hel", "hello"])
        #expect(Set(partials.map(\.utterance.id) + [final.utterance.id]).count == 1)
        #expect(final.utterance.revision == 2)
        #expect(final.utterance.confidence != nil)
    }

    @Test("failed items and realtime rate limits emit classified events")
    func failuresAndRateLimits() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(sampleRateHertz: 24_000)
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }
        try await session.start()
        try await session.submit(packet)
        try await webSocket.push(["type": "input_audio_buffer.committed", "item_id": "item_failed"])
        try await webSocket.push([
            "type": "rate_limits.updated",
            "rate_limits": [["name": "requests", "limit": 10, "remaining": 2, "reset_seconds": 1.5]],
        ])
        try await webSocket.push([
            "type": "conversation.item.input_audio_transcription.failed",
            "item_id": "item_failed",
            "content_index": 0,
            "error": ["type": "transcription_error", "message": "provider failure"],
        ])
        try await Task.sleep(for: .milliseconds(30))
        try await session.finish()
        let events = try await collector.value
        #expect(events.contains { event in
            guard case let .failure(value) = event else { return false }
            return value.context.operationID == packet.operationID && value.classification == .permanent
        })
        #expect(events.contains { event in
            guard case let .rateLimit(value) = event else { return false }
            return value.limit == 10 && value.remaining == 2 && value.retryAfterMilliseconds == 1500
        })
    }

    @Test("malformed and oversized websocket events fail generically")
    func malformedAndOversizedEvents() async throws {
        for text in ["{not-json", String(repeating: "x", count: 4 * 1024 * 1024 + 1)] {
            let webSocket = OpenAITestWebSocketTransport()
            let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
            let session = try await provider.makeSession(
                route: provider.route(model: .realtimeWhisper),
                context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
            )
            let collector = Task {
                var events: [MeetingTranscriptionProviderEvent] = []
                for try await event in session.events { events.append(event) }
                return events
            }
            try await session.start()
            await webSocket.pushText(text)
            try await Task.sleep(for: .milliseconds(30))
            let events = try await collector.value
            #expect(events.contains { if case .failure = $0 { true } else { false } })
        }
    }

    @Test("rotation warns at 55 minutes and rejects at 60 minutes")
    func rotation() async throws {
        let clock = OpenAITestClock(0)
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(
            webSocket: webSocket,
            nowMilliseconds: { clock.now() }
        )
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let collector = Task {
            var events: [MeetingTranscriptionProviderEvent] = []
            for try await event in session.events { events.append(event) }
            return events
        }
        try await session.start()
        clock.set(55 * 60 * 1000)
        try await session.submit(OpenAIMeetingTranscriptionTestFixtures.packet(
            operationID: UUID(),
            frameCount: 240,
            sampleRateHertz: 24_000
        ))
        clock.set(60 * 60 * 1000)
        await #expect(throws: OpenAIMeetingTranscriptionError.rotationRequired) {
            try await session.submit(OpenAIMeetingTranscriptionTestFixtures.packet(
                operationID: UUID(),
                startFrame: 240,
                frameCount: 240,
                sampleRateHertz: 24_000
            ))
        }
        await session.cancel()
        let events = try await collector.value
        #expect(events.contains { event in
            guard case let .warning(value) = event else { return false }
            return value.code == "realtime-session-rotation-required"
        })
    }

    @Test("realtime cancellation closes tasks and transport")
    func cancellation() async throws {
        let webSocket = OpenAITestWebSocketTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(webSocket: webSocket)
        let session = try await provider.makeSession(
            route: provider.route(model: .realtimeWhisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        try await session.start()
        await session.cancel()
        #expect(await webSocket.cancelled())
    }
}
