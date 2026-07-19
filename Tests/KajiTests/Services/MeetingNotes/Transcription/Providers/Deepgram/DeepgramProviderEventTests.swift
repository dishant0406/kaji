import Foundation
import Testing

@testable import Kaji

@Suite("Deepgram provider events")
struct DeepgramProviderEventTests {
    @Test("interims replace stable utterances and only is_final commits results")
    func interimReplacementAndFinal() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let context = try deepgramContext()
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: context
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        try await session.submit(try deepgramPacket(context: context, startFrame: 1_600, frameCount: 6_400))
        await transport.emit(.message(.text(try interimResult("hello", duration: 0.10))))
        await transport.emit(.message(.text(try interimResult("hello world", duration: 0.15))))
        await transport.emit(.message(.text(try speechFinalResult())))
        await transport.emit(.message(.text(try finalResult())))
        await transport.emit(.message(.text("{\"type\":\"SpeechStarted\",\"channel\":[0,1],\"timestamp\":0.0}")))
        await transport.emit(.message(.text("{\"type\":\"UtteranceEnd\",\"channel\":[0,1],\"last_word_end\":-1}")))
        await transport.emit(.message(.text("{\"type\":\"UtteranceEnd\",\"channel\":[0,1],\"last_word_end\":0.15}")))
        try await Task.sleep(for: .milliseconds(40))
        try await session.finish()
        let events = try await collector.value
        let transcripts = events.compactMap(deepgramTranscriptEvent)

        #expect(transcripts.count == 4)
        #expect(transcripts.map(\.kind) == [.partial, .replacement, .replacement, .final])
        #expect(Set(transcripts.map(\.utterance.id)).count == 1)
        #expect(transcripts.map(\.utterance.revision) == [0, 1, 2, 2])
        #expect(transcripts[2].kind == .replacement)
        #expect(transcripts[2].utterance.sampleRange.startFrame == 1_600)
        #expect(transcripts[2].utterance.sampleRange.endFrame == 4_000)
        #expect(transcripts[3].utterance.sampleRange == transcripts[2].utterance.sampleRange)
        #expect(events.compactMap(deepgramFailure).isEmpty)
    }

    @Test("utterance end accepts the provider no-word sentinel")
    func utteranceEndNoWordSentinel() throws {
        let event = try DeepgramStreamingEventDecoder.decode(
            "{\"type\":\"UtteranceEnd\",\"channel\":[0,1],\"last_word_end\":-1}"
        )

        #expect(event == .utteranceEnd(lastWordEnd: -1))
    }

    @Test("diarization and multilingual labels preserve stable IDs")
    func diarizationAndStableIDs() async throws {
        let context = try deepgramContext()
        let first = try await runDeepgramFinal(context: context)
        let second = try await runDeepgramFinal(context: context)

        #expect(first.id == second.id)
        #expect(first.words.map(\.id) == second.words.map(\.id))
        #expect(first.words.map(\.speakerID) == ["speaker-0", "speaker-1", "speaker-0"])
        #expect(first.words.map(\.languageCode) == ["es", "en", "es"])
        #expect(first.speaker?.id == "speaker-0")
        #expect(first.speaker?.label == "Speaker 1")
        #expect(first.language?.code == "es")
    }

    @Test("malformed and oversized events fail safely")
    func malformedAndOversizedEvents() async throws {
        for payload in ["{not-json", String(repeating: "x", count: 1100)] {
            let failure = try await failureForInvalidPayload(payload)
            #expect(failure.classification == .permanent)
            #expect(!failure.message.contains(payload))
        }
    }

    @Test("metadata emits bounded usage and provider session identity")
    func metadata() async throws {
        let transport = FakeDeepgramTransport()
        let provider = try deepgramProvider(transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        let payload = "{\"type\":\"Metadata\",\"transaction_key\":\"deprecated\"," +
            "\"request_id\":\"44444444-4444-4444-4444-444444444444\",\"sha256\":\"abc\"," +
            "\"created\":\"now\",\"duration\":1.25,\"channels\":1}"
        await transport.emit(.message(.text(payload)))
        try await Task.sleep(for: .milliseconds(20))
        try await session.finish()
        let events = try await collector.value
        let usage = try #require(events.compactMap(deepgramUsage).last)
        let completed = try #require(events.compactMap(deepgramSessionEvent).last)

        #expect(usage.metrics.first?.billingUnit == "audio-millisecond")
        #expect(usage.metrics.first?.quantity == 1250)
        #expect(completed.providerSessionID == "44444444-4444-4444-4444-444444444444")
    }

    @Test("mapping table survives a ninety-minute packet cadence and prunes finalized ranges")
    func longSessionMappings() throws {
        var mappings = DeepgramAudioMappingTable()
        let packetFrames: Int64 = 800
        let packetCount = 108_001
        for index in 0 ..< packetCount {
            let streamStart = Int64(index) * packetFrames
            mappings.append(DeepgramAudioMappingTable.Entry(
                streamStartFrame: streamStart,
                streamEndFrame: streamStart + packetFrames,
                canonicalStartFrame: 1_000_000 + streamStart,
                operationID: UUID()
            ))
        }
        let lastStreamFrame = Int64(packetCount) * packetFrames

        #expect(mappings.entries.count == packetCount)
        #expect(mappings.canonicalFrame(for: lastStreamFrame - 1, preferPreviousBoundary: false) == 1_000_000 + lastStreamFrame - 1)
        mappings.prune(through: lastStreamFrame)
        #expect(mappings.entries.isEmpty)
    }

    private func failureForInvalidPayload(_ payload: String) async throws -> MeetingTranscriptionFailureEvent {
        let transport = FakeDeepgramTransport()
        let configuration = try DeepgramNova3Configuration(
            credentialProfileID: UUID(),
            maximumEventBytes: 1024
        )
        let provider = try deepgramProvider(configuration: configuration, transport: transport)
        let session = try await provider.makeSession(
            route: provider.route(languageCodes: ["en-US"]),
            context: try deepgramContext()
        )
        let collector = collectDeepgramEvents(session.events)
        try await session.start()
        await transport.emit(.message(.text(payload)))
        let events = try await collector.value
        #expect(await transport.cancelCallCount() == 1)
        return try #require(events.compactMap(deepgramFailure).last)
    }

    private func interimResult(_ transcript: String, duration: Double) throws -> String {
        let words = transcript == "hello"
            ? [DeepgramTestWord(text: "hello", start: 0.01, end: 0.08, speaker: 0, language: "en")]
            : helloWorldWords(finalPunctuation: false)
        return try deepgramResult(
            transcript: transcript,
            duration: duration,
            isFinal: false,
            speechFinal: false,
            words: words
        )
    }

    private func speechFinalResult() throws -> String {
        try deepgramResult(
            transcript: "hello world!",
            duration: 0.15,
            isFinal: false,
            speechFinal: true,
            words: helloWorldWords(finalPunctuation: true)
        )
    }

    private func finalResult() throws -> String {
        try deepgramResult(
            transcript: "hello world!",
            duration: 0.15,
            isFinal: true,
            speechFinal: false,
            words: helloWorldWords(finalPunctuation: true)
        )
    }

    private func helloWorldWords(finalPunctuation: Bool) -> [DeepgramTestWord] {
        [
            DeepgramTestWord(text: "hello", start: 0.01, end: 0.08, speaker: 0, language: "en"),
            DeepgramTestWord(
                text: finalPunctuation ? "world!" : "world",
                start: 0.09,
                end: 0.14,
                speaker: 0,
                language: "en"
            )
        ]
    }
}
