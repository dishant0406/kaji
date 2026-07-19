import Foundation
import Testing

@testable import Kaji

@Suite("OpenAI meeting transcription provider")
struct OpenAIMeetingTranscriptionProviderTests {
    @Test("descriptor exposes exact models regions modes and privacy")
    func descriptor() throws {
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider()
        #expect(provider.descriptor.id == "openai")
        #expect(Set(provider.descriptor.models.map(\.id)) == Set(OpenAITranscriptionModel.allCases.map(\.rawValue)))
        for model in provider.descriptor.models {
            #expect(model.regions.map(\.id) == ["global"])
        }
        let diarize = try #require(provider.descriptor.model(id: OpenAITranscriptionModel.diarize.rawValue))
        #expect(diarize.capabilities.modes == [.cloudBatch])
        #expect(diarize.capabilities.diarization.availability == .supported)
        #expect(diarize.capabilities.keyterms.availability == .supported)
        #expect(!diarize.capabilities.modes.contains(.cloudRealtime))
        #expect(diarize.privacy.supportedRetention == [.none, .providerDefault])
        let realtime = try #require(provider.descriptor.model(id: OpenAITranscriptionModel.realtimeWhisper.rawValue))
        #expect(realtime.capabilities.modes == [.cloudRealtime])
        #expect(realtime.capabilities.diarization.availability == .unsupported)
        #expect(realtime.capabilities.keyterms.availability == .unsupported)
        #expect(realtime.privacy.supportedRetention == [.none, .providerDefault])
    }

    @Test("routes are exact and readiness requires a validated secret")
    func routesAndReadiness() async throws {
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider()
        for model in OpenAITranscriptionModel.allCases {
            let route = try provider.route(model: model, languageCode: "en")
            #expect(route.modelID == model.rawValue)
            #expect(route.mode == model.mode)
            #expect(route.regionID == OpenAITranscriptionRegion.global.rawValue)
            #expect(route.diarizationEnabled == model.isDiarizing)
            #expect(await provider.readiness(for: route).state == .ready)
        }
        let missing = try OpenAIMeetingTranscriptionTestFixtures.provider(
            secretResolver: OpenAITestSecretResolver(error: STTCredentialStoreError.credentialUnavailable)
        )
        let route = try missing.route(model: .whisper)
        #expect(await missing.readiness(for: route).state == .requiresConfiguration)
    }

    @Test("batch authorization is confined to the exact origin and errors redact credentials")
    func authorizationAndRedaction() async throws {
        let response = try OpenAIMeetingTranscriptionTestFixtures.response(body: #"{"text":"hello"}"#)
        let http = OpenAITestHTTPTransport(responses: [.success(response)])
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http, region: .eu)
        let route = try provider.route(model: .transcribe, region: .eu, languageCode: "en")
        let session = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context()
        )
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet()
        _ = try await OpenAIMeetingTranscriptionTestFixtures.collect(session: session) {
            try await session.start()
            await #expect(throws: OpenAIMeetingTranscriptionError.self) {
                try await session.submit(packet)
            }
            await session.cancel()
        }
        let request = try #require(await http.capturedRequests().first)
        #expect(request.url?.absoluteString == "https://eu.api.openai.com/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(OpenAIMeetingTranscriptionTestFixtures.token)")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.value(forHTTPHeaderField: "Pragma") == "no-cache")
        let error = OpenAIMeetingTranscriptionError.invalidResponse
        #expect(!String(describing: error).contains(OpenAIMeetingTranscriptionTestFixtures.token))
    }

    @Test("batch multipart enforces the complete 25 MB upload limit")
    func uploadLimit() async throws {
        let http = OpenAITestHTTPTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http)
        let route = try provider.route(model: .transcribe)
        let session = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context(sampleRateHertz: 24_000)
        )
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(
            frameCount: 13 * 1024 * 1024,
            sampleRateHertz: 24_000
        )
        try await session.start()
        await #expect(throws: OpenAIMeetingTranscriptionError.audioTooLarge) {
            try await session.submit(packet)
        }
        await session.cancel()
        #expect(await http.capturedRequests().isEmpty)
    }

    @Test("batch parses whisper words GPT JSON and GPT text")
    func batchFormats() async throws {
        let whisper = try OpenAIMeetingTranscriptionTestFixtures.response(
            body: #"{"task":"transcribe","language":"en","duration":1,"text":"hello world","words":[{"word":"hello","start":0.0,"end":0.4},{"word":"world","start":0.4,"end":1.0}]}"#
        )
        let json = try OpenAIMeetingTranscriptionTestFixtures.response(body: #"{"text":"json transcript"}"#)
        let text = try OpenAIMeetingTranscriptionTestFixtures.response(
            body: "plain transcript",
            contentType: "text/plain; charset=utf-8"
        )
        let http = OpenAITestHTTPTransport(responses: [.success(whisper), .success(json), .success(text)])
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http)
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet()
        var values: [(OpenAITranscriptionModel, String, Int)] = []
        for model in [OpenAITranscriptionModel.whisper, .transcribe, .miniTranscribe] {
            let session = try await provider.makeSession(
                route: provider.route(model: model, languageCode: "en"),
                context: OpenAIMeetingTranscriptionTestFixtures.context()
            )
            let events = try await OpenAIMeetingTranscriptionTestFixtures.collect(session: session) {
                try await session.start()
                try await session.submit(packet)
                try await session.finish()
            }
            let final = try #require(events.compactMap { event -> MeetingTranscriptionFinalEvent? in
                guard case let .final(value) = event else { return nil }
                return value
            }.first)
            values.append((model, final.utterance.text, final.utterance.words.count))
        }
        #expect(values.map(\.1) == ["hello world", "json transcript", "plain transcript"])
        #expect(values.map(\.2) == [2, 0, 0])
    }

    @Test("diarized JSON emits stable ranged speakers and requires audio")
    func diarization() async throws {
        let body = #"{"text":"hello there","segments":[{"start":0.0,"end":0.5,"text":"hello","speaker":"A"},{"start":0.5,"end":1.0,"text":"there","speaker":"B"}]}"#
        let responses = try [
            OpenAIMeetingTranscriptionTestFixtures.response(body: body),
            OpenAIMeetingTranscriptionTestFixtures.response(body: body),
        ]
        let http = OpenAITestHTTPTransport(responses: responses.map(Result.success))
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http)
        let route = try provider.route(model: .diarize)
        let operationID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet(operationID: operationID)
        var runs: [[MeetingTranscriptionFinalEvent]] = []
        for _ in 0 ..< 2 {
            let session = try await provider.makeSession(
                route: route,
                context: OpenAIMeetingTranscriptionTestFixtures.context()
            )
            let events = try await OpenAIMeetingTranscriptionTestFixtures.collect(session: session) {
                try await session.start()
                try await session.submit(packet)
                try await session.finish()
            }
            runs.append(events.compactMap { event in
                guard case let .final(value) = event else { return nil }
                return value
            })
        }
        #expect(runs[0].map(\.utterance.id) == runs[1].map(\.utterance.id))
        #expect(runs[0].map(\.utterance.speaker?.id) == ["speaker-a", "speaker-b"])
        #expect(runs[0].map(\.utterance.sampleRange.startFrame) == [0, 8_000])
        let requestBody = try #require(await http.capturedRequests().first?.httpBody)
        let requestText = String(decoding: requestBody, as: UTF8.self)
        #expect(!requestText.contains("name=\"prompt\""))
        #expect(!requestText.contains("Kaji, Muxy"))
        let empty = try await provider.makeSession(
            route: route,
            context: OpenAIMeetingTranscriptionTestFixtures.context()
        )
        try await empty.start()
        await #expect(throws: OpenAIMeetingTranscriptionError.audioBatchRequired) {
            try await empty.finish()
        }
        await empty.cancel()
    }

    @Test("diarized SSE segments emit speaker-timed finals without an aggregate duplicate")
    func diarizedServerSentEvents() async throws {
        let body = "data: {\"type\":\"transcript.text.segment\",\"id\":\"seg_0\",\"start\":0.0,\"end\":0.5,\"text\":\"hello\",\"speaker\":\"A\"}\n\n" +
            "data: {\"type\":\"transcript.text.segment\",\"id\":\"seg_1\",\"start\":0.5,\"end\":1.0,\"text\":\"there\",\"speaker\":\"B\"}\n\n" +
            "data: {\"type\":\"transcript.text.done\",\"text\":\"hello there\"}\n\n" +
            "data: [DONE]\n\n"
        let http = OpenAITestHTTPTransport(responses: [
            .success(try OpenAIMeetingTranscriptionTestFixtures.response(body: body, contentType: "text/event-stream")),
        ])
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http, stream: true)
        let session = try await provider.makeSession(
            route: provider.route(model: .diarize),
            context: OpenAIMeetingTranscriptionTestFixtures.context()
        )
        let events = try await OpenAIMeetingTranscriptionTestFixtures.collect(session: session) {
            try await session.start()
            try await session.submit(OpenAIMeetingTranscriptionTestFixtures.packet())
            try await session.finish()
        }
        let finals = events.compactMap { event -> MeetingTranscriptionFinalEvent? in
            guard case let .final(value) = event else { return nil }
            return value
        }

        #expect(finals.map(\.utterance.text) == ["hello", "there"])
        #expect(finals.map(\.utterance.speaker?.id) == ["speaker-a", "speaker-b"])
        #expect(finals.map(\.utterance.sampleRange.startFrame) == [0, 8_000])
        #expect(finals.map(\.utterance.sampleRange.endFrame) == [8_000, 16_000])
    }

    @Test("JSON node budget is aggregate across sibling containers")
    func aggregateJSONNodeBudget() throws {
        let values = Array(repeating: NSNull(), count: 10_000)
        let withinBudget = try JSONSerialization.data(withJSONObject: [
            "a": values, "b": values, "c": values, "d": values,
        ])
        let overBudget = try JSONSerialization.data(withJSONObject: [
            "a": values, "b": values, "c": values, "d": values, "e": values,
        ])

        _ = try OpenAIJSON.object(withinBudget, maximumBytes: withinBudget.count)
        #expect(throws: OpenAIMeetingTranscriptionError.invalidResponse) {
            try OpenAIJSON.object(overBudget, maximumBytes: overBudget.count)
        }
    }

    @Test("SSE emits bounded partials and final and rejects malformed events")
    func serverSentEvents() async throws {
        let valid = "data: {\"type\":\"transcript.text.delta\",\"delta\":\"hel\",\"segment_id\":\"seg_123\"}\n\n" +
            "data: {\"type\":\"transcript.text.done\",\"text\":\"hello\"}\n\n"
        let malformed = "data: {\"type\":\"unknown\",\"secret\":\"value\"}\n\n"
        let http = OpenAITestHTTPTransport(responses: [
            .success(try OpenAIMeetingTranscriptionTestFixtures.response(body: valid, contentType: "text/event-stream")),
            .success(try OpenAIMeetingTranscriptionTestFixtures.response(body: malformed, contentType: "text/event-stream")),
        ])
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http, stream: true)
        let route = try provider.route(model: .transcribe)
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet()
        let session = try await provider.makeSession(route: route, context: OpenAIMeetingTranscriptionTestFixtures.context())
        let events = try await OpenAIMeetingTranscriptionTestFixtures.collect(session: session) {
            try await session.start()
            try await session.submit(packet)
            try await session.finish()
        }
        #expect(events.contains { if case .partial = $0 { true } else { false } })
        #expect(events.contains { if case .final = $0 { true } else { false } })
        let invalid = try await provider.makeSession(route: route, context: OpenAIMeetingTranscriptionTestFixtures.context())
        try await invalid.start()
        await #expect(throws: OpenAIMeetingTranscriptionError.invalidResponse) {
            try await invalid.submit(packet)
        }
        await invalid.cancel()
    }

    @Test("HTTP rate limits and oversized responses are classified")
    func rateLimitsAndBounds() async throws {
        let rateLimited = try OpenAIMeetingTranscriptionTestFixtures.response(
            status: 429,
            body: #"{"error":{"message":"slow","type":"requests","param":null,"code":"rate_limit"}}"#,
            headers: ["Retry-After": "2"]
        )
        let oversized = try OpenAIHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(repeating: 1, count: 1025),
            finalURL: OpenAIEndpoint.batch(try OpenAIMeetingTranscriptionTestFixtures.endpoint())
        )
        let http = OpenAITestHTTPTransport(responses: [.success(rateLimited), .success(oversized)])
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http, maximumResponseBytes: 1024)
        let route = try provider.route(model: .transcribe)
        let packet = try OpenAIMeetingTranscriptionTestFixtures.packet()
        let first = try await provider.makeSession(route: route, context: OpenAIMeetingTranscriptionTestFixtures.context())
        try await first.start()
        await #expect(throws: OpenAIMeetingTranscriptionError.rateLimited) {
            try await first.submit(packet)
        }
        await first.cancel()
        let second = try await provider.makeSession(route: route, context: OpenAIMeetingTranscriptionTestFixtures.context())
        try await second.start()
        await #expect(throws: OpenAIMeetingTranscriptionError.responseTooLarge) {
            try await second.submit(packet)
        }
        await second.cancel()
    }

    @Test("cancellation cancels the injected batch transport")
    func cancellation() async throws {
        let http = OpenAITestHTTPTransport()
        let provider = try OpenAIMeetingTranscriptionTestFixtures.provider(http: http)
        let session = try await provider.makeSession(
            route: provider.route(model: .whisper),
            context: OpenAIMeetingTranscriptionTestFixtures.context()
        )
        try await session.start()
        await session.cancel()
        #expect(await http.cancelled())
    }
}
