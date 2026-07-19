import Foundation
import Testing

@testable import Kaji

@Suite("Deepgram provider requests")
struct DeepgramProviderRequestTests {
    @Test("descriptor advertises realtime capabilities, retention, and concurrency")
    func descriptor() throws {
        let provider = try deepgramProvider(transport: FakeDeepgramTransport())

        #expect(provider.descriptor.models.map(\.id) == [DeepgramMeetingTranscriptionProvider.multilingualModelID])
        #expect(provider.descriptor.models.allSatisfy { $0.capabilities.modes == [.cloudRealtime] })
        #expect(provider.descriptor.metadata["dynamicModels"] == "true")
        #expect(provider.descriptor.models.allSatisfy {
            $0.privacy.supportedRetention == [.none, .providerDefault]
        })
        #expect(provider.descriptor.models.allSatisfy { model in
            model.regions.map(\.id) == [DeepgramMeetingTranscriptionProvider.globalRegionID]
        })
    }

    @Test("requests use exact regional endpoints and strict query options")
    func regionalRequests() throws {
        let context = try deepgramContext(keyterms: ["Kaji", "meeting notes"])
        let configuration = try DeepgramNova3Configuration(credentialProfileID: UUID())
        let regions = [
            (DeepgramMeetingTranscriptionProvider.globalRegionID, "api.deepgram.com"),
            (DeepgramMeetingTranscriptionProvider.europeRegionID, "api.eu.deepgram.com"),
            (DeepgramMeetingTranscriptionProvider.australiaRegionID, "api.au.deepgram.com"),
        ]

        for (regionID, host) in regions {
            let route = try MeetingTranscriptionRoute(
                providerID: DeepgramMeetingTranscriptionProvider.providerID,
                modelID: DeepgramMeetingTranscriptionProvider.multilingualModelID,
                languageCodes: ["en-US"],
                regionID: regionID,
                mode: .cloudRealtime,
                diarizationEnabled: true,
                retention: .none
            )
            let request = try DeepgramStreamingRequestFactory.makeRequest(
                route: route,
                context: context,
                configuration: configuration,
                endpoint: try #require(URL(string: "wss://\(host)/v1/listen")),
                apiKey: "secret-key"
            )
            try verifyMonolingualRequest(request, host: host)
        }
    }

    @Test("multilingual requests use language multi and preserve provider retention")
    func multilingualRequest() throws {
        let context = try deepgramContext()
        let configuration = try DeepgramNova3Configuration(credentialProfileID: UUID())
        let route = try MeetingTranscriptionRoute(
            providerID: DeepgramNova3MeetingTranscriptionProvider.providerID,
            modelID: DeepgramNova3MeetingTranscriptionProvider.multilingualModelID,
            languageCodes: ["en", "es"],
            regionID: DeepgramNova3MeetingTranscriptionProvider.globalRegionID,
            mode: .cloudRealtime,
            diarizationEnabled: true,
            retention: .providerDefault
        )
        let request = try DeepgramStreamingRequestFactory.makeRequest(
            route: route,
            context: context,
            configuration: configuration,
            endpoint: try #require(URL(string: "wss://api.deepgram.com/v1/listen")),
            apiKey: "secret-key"
        )
        let query = try requestQuery(request)

        #expect(query["language"]?.map(\.value) == ["multi"])
        #expect(query["mip_opt_out"] == nil)
    }

    @Test("binary audio, keepalive, finalize, and close stream use correct frames")
    func framesAndFinish() async throws {
        let transport = FakeDeepgramTransport()
        let ticks = ManualDeepgramTicks()
        let provider = try deepgramProvider(transport: transport, ticks: ticks)
        let context = try deepgramContext()
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: context
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        ticks.tick()
        try await waitForDeepgram { await transport.sentMessages().contains(.text("{\"type\":\"KeepAlive\"}")) }
        let packet = try deepgramPacket(context: context, startFrame: 1_600, frameCount: 4_800)
        try await session.submit(packet)
        ticks.tick()
        ticks.tick()
        try await Task.sleep(for: .milliseconds(20))
        try await session.finish()
        try await session.finish()
        let sent = await transport.sentMessages()
        let binary = sent.compactMap { message -> Data? in
            guard case let .binary(data) = message else { return nil }
            return data
        }
        let events = try await collector.value

        #expect(binary == [packet.bytes])
        #expect(sent.suffix(2) == [.text("{\"type\":\"Finalize\"}"), .text("{\"type\":\"CloseStream\"}")])
        #expect(await transport.closeCallCount() == 1)
        #expect(events.compactMap(deepgramSessionState).suffix(2) == [.draining, .completed])
    }

    @Test("one session accepts replay but requires orchestrator reconnect for a new epoch")
    func replayEpochContract() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let context = try deepgramContext()
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: context
        )
        let replayEpoch = try #require(MeetingProviderEpoch(rawValue: 1))
        let nextEpoch = try #require(MeetingProviderEpoch(rawValue: 2))
        try await session.start()
        try await session.submit(try deepgramPacket(
            context: context,
            startFrame: 1_600,
            frameCount: 1_600,
            providerEpoch: replayEpoch,
            isReplay: true
        ))
        let nextPacket = try deepgramPacket(
            context: context,
            startFrame: 3_200,
            frameCount: 1_600,
            providerEpoch: nextEpoch
        )
        await #expect(throws: DeepgramMeetingTranscriptionError.invalidPacket) {
            try await session.submit(nextPacket)
        }
        #expect(await transport.connectCallCount() == 1)
        await session.cancel()
    }

    private func verifyMonolingualRequest(_ request: URLRequest, host: String) throws {
        let query = try requestQuery(request)
        let url = try #require(request.url)

        #expect(url.scheme == "wss")
        #expect(url.host == host)
        #expect(url.path == "/v1/listen")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token secret-key")
        #expect(request.allHTTPHeaderFields?.count == 1)
        #expect(url.query?.contains("secret-key") == false)
        #expect(query["model"]?.map(\.value) == [DeepgramMeetingTranscriptionProvider.multilingualModelID])
        #expect(query["encoding"]?.map(\.value) == ["linear16"])
        #expect(query["sample_rate"]?.map(\.value) == ["16000"])
        #expect(query["channels"]?.map(\.value) == ["1"])
        #expect(query["interim_results"]?.map(\.value) == ["true"])
        #expect(query["endpointing"]?.map(\.value) == ["300"])
        #expect(query["utterance_end_ms"]?.map(\.value) == ["1000"])
        #expect(query["smart_format"]?.map(\.value) == ["true"])
        #expect(query["diarize_model"]?.map(\.value) == ["latest"])
        #expect(query["diarize"] == nil)
        #expect(query["vad_events"]?.map(\.value) == ["true"])
        #expect(query["language"]?.map(\.value) == ["en-US"])
        #expect(query["keyterm"]?.compactMap(\.value) == ["Kaji", "meeting notes"])
        #expect(query["mip_opt_out"]?.map(\.value) == ["true"])
    }

    @Test("keyterms reject count character and conservative token estimate overflow")
    func keytermBounds() throws {
        try DeepgramNova3MeetingTranscriptionProvider.validateKeyterms(Array(0 ..< 100).map { "term\($0)" })

        #expect(throws: DeepgramMeetingTranscriptionError.invalidConfiguration) {
            try DeepgramNova3MeetingTranscriptionProvider.validateKeyterms(Array(0 ... 100).map { "term\($0)" })
        }
        #expect(throws: DeepgramMeetingTranscriptionError.invalidConfiguration) {
            try DeepgramNova3MeetingTranscriptionProvider.validateKeyterms([String(repeating: "x", count: 2001)])
        }
        #expect(throws: DeepgramMeetingTranscriptionError.invalidConfiguration) {
            try DeepgramNova3MeetingTranscriptionProvider.validateKeyterms(
                Array(0 ..< 100).map { "\($0)-" + String(repeating: "x", count: 12) }
            )
        }
    }

    private func requestQuery(_ request: URLRequest) throws -> [String: [URLQueryItem]] {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(grouping: components.queryItems ?? [], by: \.name)
    }
}
