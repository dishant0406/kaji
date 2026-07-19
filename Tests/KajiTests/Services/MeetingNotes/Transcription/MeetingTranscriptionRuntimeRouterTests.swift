import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcription runtime router")
struct MeetingTranscriptionRuntimeRouterTests {
    @Test("queue capacity is derived from transcription mode")
    func queueCapacityByMode() {
        #expect(MeetingTranscriptionRuntimeRouter.packetCapacity(for: .cloudRealtime) == 512)
        #expect(MeetingTranscriptionRuntimeRouter.packetCapacity(for: .cloudBatch) == 32)
        #expect(MeetingTranscriptionRuntimeRouter.packetCapacity(for: .localChunked) == 16)
    }

    @Test("a blocked source does not prevent another source from completing")
    func independentTracks() async throws {
        let blockedTrackID = UUID()
        let activeTrackID = UUID()
        let lifecycle = RouterSessionLifecycleRecorder()
        let provider = try RouterTestProvider(blockedTrackID: blockedTrackID, lifecycle: lifecycle)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            packetCapacity: 2,
            eventHandler: { await recorder.record($0) }
        )
        let sessionID = UUID()
        let blocked = try packet(sessionID: sessionID, trackID: blockedTrackID, source: .microphone, operationID: UUID())
        let activeID = UUID()
        let active = try packet(sessionID: sessionID, trackID: activeTrackID, source: .systemAudio, operationID: activeID)

        try await router.submit(blocked, context: try context(for: blocked))
        try await router.submit(active, context: try context(for: active))
        await recorder.waitForFinal(id: activeID)
        await lifecycle.waitForStarted(trackIDs: [blockedTrackID, activeTrackID])

        #expect(await recorder.finalIDs().contains(activeID))
        await router.cancel()
        #expect(Set(await lifecycle.cancelledTrackIDs()) == [blockedTrackID, activeTrackID])
    }

    @Test("partial and final revisions materialize while provider metadata is forwarded")
    func revisionAndMetadataEvents() async throws {
        let lifecycle = RouterSessionLifecycleRecorder()
        let provider = try RouterTestProvider(scripted: true, lifecycle: lifecycle)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            eventHandler: { await recorder.record($0) }
        )
        let operationID = UUID()
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: operationID
        )

        try await router.submit(packet, context: try context(for: packet))
        await router.finish()

        let segments = await recorder.segments()
        #expect(segments.map(\.id) == [operationID, operationID])
        #expect(segments.map(\.text) == ["draft", "final"])
        #expect(segments.map(\.isFinal) == [false, true])
        #expect(await recorder.warningCount() == 1)
        #expect(await recorder.usageCount() == 1)
        #expect(await recorder.rateLimitCount() == 1)
        #expect(await recorder.sessionCount() == 1)
        #expect(await lifecycle.finishedTrackIDs() == [packet.trackID])
        #expect(await lifecycle.cancelledTrackIDs().isEmpty)
    }

    @Test("cancel closes every created track session")
    func cancelAllTracks() async throws {
        let lifecycle = RouterSessionLifecycleRecorder()
        let provider = try RouterTestProvider(blockAll: true, lifecycle: lifecycle)
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            eventHandler: { _ in }
        )
        let sessionID = UUID()
        let packets = try [
            packet(sessionID: sessionID, trackID: UUID(), source: .microphone, operationID: UUID()),
            packet(sessionID: sessionID, trackID: UUID(), source: .systemAudio, operationID: UUID()),
        ]
        for packet in packets {
            try await router.submit(packet, context: context(for: packet))
        }
        await lifecycle.waitForStarted(trackIDs: Set(packets.map(\.trackID)))

        await router.cancel()

        #expect(Set(await lifecycle.cancelledTrackIDs()) == Set(packets.map(\.trackID)))
        await #expect(throws: MeetingTranscriptionRuntimeRouterError.self) {
            try await router.submit(packets[0], context: context(for: packets[0]))
        }
    }

    @Test("disconnect creates a new epoch and replays retained audio")
    func reconnectAfterDisconnect() async throws {
        let script = ReconnectScript(scenario: .disconnect)
        let provider = try ReconnectProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let policy = try retryPolicy()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: policy,
            sleep: { _ in },
            retryDelay: { $0.lowerBound },
            eventHandler: { await recorder.record($0) }
        )
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: UUID()
        )

        try await router.submit(packet, context: context(for: packet))
        await script.waitForSessionCount(2)
        await script.waitForEpoch(1)
        await router.finish()

        let submissions = await script.submissions()
        #expect(submissions.contains { $0.providerEpoch.rawValue == 1 && $0.isReplay })
        #expect(await recorder.healthStates().contains(.reconnecting))
    }

    @Test("normal event completion during finish waits for provider drain without reconnecting")
    func eventCompletionDuringFinish() async throws {
        let script = CleanFinishScript()
        let provider = try CleanFinishProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            eventHandler: { await recorder.record($0) }
        )
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: UUID()
        )
        try await router.submit(packet, context: context(for: packet))

        let finishing = Task { await router.finish() }
        await script.waitForFinishStarted()
        for _ in 0 ..< 100 { await Task.yield() }

        #expect(await script.sessionCount() == 1)
        #expect(await script.cancelCount() == 0)
        let healthStates = await recorder.healthStates()
        #expect(!healthStates.contains(.reconnecting))
        await script.releaseFinish()
        await finishing.value
        #expect(await script.finishReturned())
        #expect(await script.cancelCount() == 0)
    }

    @Test("thirty seconds of realtime replay stays within outstanding commit capacity")
    func pacedRealtimeReplay() async throws {
        let script = PacedReplayScript(packetCount: 300)
        let provider = try PacedReplayProvider(script: script)
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: try realtimeRoute(),
            packetCapacity: 512,
            retryPolicy: retryPolicy(),
            replaySleep: { milliseconds in await script.pacingTick(milliseconds: milliseconds) },
            retryDelay: { $0.lowerBound },
            eventHandler: { _ in }
        )
        let sessionID = UUID()
        let trackID = UUID()
        for index in 0 ..< 300 {
            let packet = try packet(
                sessionID: sessionID,
                trackID: trackID,
                source: .microphone,
                operationID: UUID(),
                startFrame: Int64(index * 1_600),
                frameCount: 1_600
            )
            try await router.submit(packet, context: context(for: packet))
        }

        await script.waitForReplayCount(300)
        await router.finish()

        #expect(await script.maximumOutstandingReplayCount() <= MeetingTranscriptionBufferPolicy.maximumOutstandingRealtimeCommits)
        #expect(await script.totalPacedMilliseconds() == 30_000)
    }

    @Test("rate limit honors retry-after before reconnecting")
    func reconnectAfterRateLimit() async throws {
        let script = ReconnectScript(scenario: .rateLimited)
        let provider = try ReconnectProvider(script: script)
        let delays = RetryDelayRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: retryPolicy(),
            sleep: { await delays.record($0) },
            retryDelay: { $0.lowerBound },
            eventHandler: { _ in }
        )
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: UUID()
        )

        try await router.submit(packet, context: context(for: packet))
        await script.waitForSessionCount(2)
        await router.finish()

        #expect(await delays.values() == [750])
    }

    @Test("rotation warning actively replaces the provider session")
    func rotationWarningReconnects() async throws {
        let script = ReconnectScript(scenario: .rotation)
        let provider = try ReconnectProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: retryPolicy(),
            sleep: { _ in },
            eventHandler: { await recorder.record($0) }
        )
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: UUID()
        )

        try await router.submit(packet, context: context(for: packet))
        await script.waitForSessionCount(2)
        await script.waitForEpoch(1)
        await router.finish()

        #expect(await recorder.warningCount() == 1)
        #expect(await script.submissions().contains { $0.providerEpoch.rawValue == 1 })
    }

    @Test("replay cutover rejects seam duplicates and stale epoch events")
    func replayCutoverAndStaleEvents() async throws {
        let script = ReconnectScript(scenario: .seam)
        let provider = try ReconnectProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: retryPolicy(),
            sleep: { _ in },
            eventHandler: { await recorder.record($0) }
        )
        let sessionID = UUID()
        let trackID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let first = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: firstID,
            startFrame: 0
        )
        let second = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: secondID,
            startFrame: 2
        )

        try await router.submit(first, context: context(for: first))
        await recorder.waitForFinal(id: firstID)
        try await router.submit(second, context: context(for: second))
        await script.waitForSessionCount(2)
        await recorder.waitForFinal(id: secondID)
        await router.finish()

        #expect(await recorder.finalIDs() == [firstID, secondID])
    }

    @Test("out-of-order later finals do not advance cutover past uncommitted audio")
    func contiguousReplayCutover() async throws {
        let script = ReconnectScript(scenario: .outOfOrder)
        let provider = try ReconnectProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: retryPolicy(),
            sleep: { _ in },
            eventHandler: { await recorder.record($0) }
        )
        let sessionID = UUID()
        let trackID = UUID()
        let firstID = UUID()
        let laterID = UUID()
        let failureID = UUID()
        let first = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: firstID,
            startFrame: 0
        )
        let later = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: laterID,
            startFrame: 2
        )
        let failure = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: failureID,
            startFrame: 4
        )

        try await router.submit(first, context: context(for: first))
        try await router.submit(later, context: context(for: later))
        await recorder.waitForFinal(id: laterID)
        try await router.submit(failure, context: context(for: failure))
        await script.waitForSessionCount(2)
        await recorder.waitForFinal(id: firstID)
        await router.finish()

        #expect(await recorder.finalIDs().contains(firstID))
    }

    @Test("exhausted retry persists ranges while capture submissions continue")
    func exhaustedRetryCreatesGaps() async throws {
        let script = ReconnectScript(scenario: .permanent)
        let provider = try ReconnectProvider(script: script)
        let recorder = RouterRuntimeEventRecorder()
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: provider,
            route: MeetingTranscriptionCoreFixtures.route(),
            retryPolicy: retryPolicy(),
            sleep: { _ in },
            eventHandler: { await recorder.record($0) }
        )
        let sessionID = UUID()
        let trackID = UUID()
        let first = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: UUID()
        )
        let second = try packet(
            sessionID: sessionID,
            trackID: trackID,
            source: .microphone,
            operationID: UUID(),
            startFrame: 2
        )

        try await router.submit(first, context: context(for: first))
        await recorder.waitForHealth(.failed)
        try await router.submit(second, context: context(for: second))
        await router.finish()

        #expect(await recorder.failureRanges().contains(second.sampleRange))
    }

    @Test("retry exhaustion hands replay to the resolved local fallback")
    func localFallbackHandoff() async throws {
        let primaryScript = ReconnectScript(scenario: .permanent)
        let fallbackScript = ReconnectScript(scenario: .success)
        let primary = try ReconnectProvider(script: primaryScript)
        let local = try ReconnectProvider(script: fallbackScript)
        let recorder = RouterRuntimeEventRecorder()
        let route = try MeetingTranscriptionCoreFixtures.route()
        let policy = try MeetingTranscriptionRetryPolicy(
            maximumAttempts: 1,
            baseDelayMilliseconds: 0,
            maximumDelayMilliseconds: 0,
            retryableClassifications: [.transient]
        )
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: primary,
            route: route,
            fallback: MeetingTranscriptionRuntimeFallback(provider: local, route: route),
            retryPolicy: policy,
            sleep: { _ in },
            eventHandler: { await recorder.record($0) }
        )
        let packet = try packet(
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            operationID: UUID()
        )

        try await router.submit(packet, context: context(for: packet))
        await fallbackScript.waitForEpoch(1)
        await router.finish()

        #expect(await recorder.healthStates().contains(.localFallback))
        #expect(await fallbackScript.submissions().contains { $0.providerEpoch.rawValue == 1 && $0.isReplay })
    }

    @Test("provider-neutral audio and core boundaries do not reference SpeechInput")
    func providerNeutralBoundary() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let paths = [
            "Kaji/Services/MeetingNotes/Audio",
            "Kaji/Services/MeetingNotes/Transcription/Core",
        ]
        for path in paths {
            let directory = root.appendingPathComponent(path, isDirectory: true)
            let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let file as URL in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                #expect(!source.contains("SpeechInput"), "Unexpected SpeechInput dependency in \(file.path)")
                #expect(!source.contains("SpeechAudioChunk"), "Unexpected SpeechAudioChunk dependency in \(file.path)")
            }
        }
    }

    private func packet(
        sessionID: UUID,
        trackID: UUID,
        source: MeetingTranscriptionSource,
        operationID: UUID,
        startFrame: Int64 = 0,
        frameCount: Int64 = 2
    ) throws -> MeetingNormalizedAudioPacket {
        let sampleCount = Int(frameCount)
        return try MeetingNormalizedAudioPacket(
            operationID: operationID,
            sessionID: sessionID,
            trackID: trackID,
            source: source,
            sampleRange: MeetingCanonicalSampleRange(
                startFrame: startFrame,
                endFrame: startFrame + frameCount,
                sampleRateHertz: 16_000
            ),
            encoding: .pcmFloat32LittleEndian,
            sampleRateHertz: 16_000,
            channelCount: 1,
            bytes: [Float](repeating: 0.25, count: sampleCount)
                .map { $0.bitPattern.littleEndian }
                .withUnsafeBytes { Data($0) },
            providerEpoch: .initial
        )
    }

    private func context(for packet: MeetingNormalizedAudioPacket) throws -> MeetingTrackTranscriptionContextSnapshot {
        try MeetingTrackTranscriptionContextSnapshot(
            sessionID: packet.sessionID,
            trackID: packet.trackID,
            source: packet.source,
            canonicalSampleRateHertz: packet.sampleRateHertz,
            channelCount: packet.channelCount,
            startedAtMilliseconds: 1_000
        )
    }

    private func retryPolicy() throws -> MeetingTranscriptionRetryPolicy {
        try MeetingTranscriptionRetryPolicy(
            maximumAttempts: 2,
            baseDelayMilliseconds: 100,
            maximumDelayMilliseconds: 1_000,
            retryableClassifications: [.transient, .rateLimited, .unavailable]
        )
    }

    private func realtimeRoute() throws -> MeetingTranscriptionRoute {
        try MeetingTranscriptionRoute(
            providerID: "test-provider",
            modelID: "test-model",
            languageCodes: ["en-US"],
            regionID: "local",
            mode: .cloudRealtime,
            diarizationEnabled: true,
            retention: .none
        )
    }
}

private actor CleanFinishScript {
    private var createdSessionCount = 0
    private var cancellations = 0
    private var finishStartedValue = false
    private var finishReleased = false
    private var finishReturnedValue = false

    func recordSession() {
        createdSessionCount += 1
    }

    func recordCancel() {
        cancellations += 1
    }

    func recordFinishStarted() {
        finishStartedValue = true
    }

    func waitForFinishStarted() async {
        while !finishStartedValue { await Task.yield() }
    }

    func waitForFinishRelease() async {
        while !finishReleased { await Task.yield() }
    }

    func releaseFinish() {
        finishReleased = true
    }

    func recordFinishReturned() {
        finishReturnedValue = true
    }

    func sessionCount() -> Int {
        createdSessionCount
    }

    func cancelCount() -> Int {
        cancellations
    }

    func finishReturned() -> Bool {
        finishReturnedValue
    }
}

private final class CleanFinishProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    let descriptor: MeetingTranscriptionProviderDescriptor
    private let script: CleanFinishScript

    init(script: CleanFinishScript) throws {
        descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
        self.script = script
    }

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context _: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        await script.recordSession()
        return CleanFinishSession(script: script)
    }
}

private actor CleanFinishSession: MeetingTrackTranscriptionSession {
    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let script: CleanFinishScript
    private let continuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation

    init(script: CleanFinishScript) {
        self.script = script
        var streamContinuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation!
        events = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func start() async throws {}

    func submit(_: MeetingNormalizedAudioPacket) async throws {}

    func finish() async throws {
        await script.recordFinishStarted()
        continuation.finish()
        await script.waitForFinishRelease()
        await script.recordFinishReturned()
    }

    func cancel() async {
        await script.recordCancel()
        continuation.finish()
    }
}

private actor PacedReplayScript {
    private let packetCount: Int
    private var createdSessionCount = 0
    private var initialSubmissionCount = 0
    private var replaySubmissionCount = 0
    private var outstandingReplayCount = 0
    private var maximumOutstanding = 0
    private var pacedMilliseconds: Int64 = 0

    init(packetCount: Int) {
        self.packetCount = packetCount
    }

    func nextSessionIndex() -> Int {
        defer { createdSessionCount += 1 }
        return createdSessionCount
    }

    func record(_ packet: MeetingNormalizedAudioPacket) throws -> Bool {
        if packet.providerEpoch == .initial {
            initialSubmissionCount += 1
            return initialSubmissionCount == packetCount
        }
        guard outstandingReplayCount < MeetingTranscriptionBufferPolicy.maximumOutstandingRealtimeCommits else {
            throw OpenAIMeetingTranscriptionError.invalidState
        }
        replaySubmissionCount += 1
        outstandingReplayCount += 1
        maximumOutstanding = max(maximumOutstanding, outstandingReplayCount)
        return false
    }

    func pacingTick(milliseconds: Int64) {
        pacedMilliseconds += milliseconds
        outstandingReplayCount = max(0, outstandingReplayCount - 1)
    }

    func waitForReplayCount(_ count: Int) async {
        while replaySubmissionCount < count { await Task.yield() }
    }

    func maximumOutstandingReplayCount() -> Int {
        maximumOutstanding
    }

    func totalPacedMilliseconds() -> Int64 {
        pacedMilliseconds
    }
}

private final class PacedReplayProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    let descriptor: MeetingTranscriptionProviderDescriptor
    private let script: PacedReplayScript

    init(script: PacedReplayScript) throws {
        descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
        self.script = script
    }

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        PacedReplaySession(
            index: await script.nextSessionIndex(),
            context: try MeetingTrackTranscriptionContextSnapshot(
                sessionID: context.sessionID,
                trackID: context.trackID,
                source: context.source,
                canonicalSampleRateHertz: context.canonicalSampleRateHertz,
                channelCount: context.channelCount,
                startedAtMilliseconds: context.startedAtMilliseconds,
                keyterms: context.keyterms
            ),
            script: script
        )
    }
}

private actor PacedReplaySession: MeetingTrackTranscriptionSession {
    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let index: Int
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let script: PacedReplayScript
    private let continuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation

    init(index: Int, context: MeetingTrackTranscriptionContextSnapshot, script: PacedReplayScript) {
        self.index = index
        self.context = context
        self.script = script
        var streamContinuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation!
        events = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func start() async throws {}

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        let shouldFail = try await script.record(packet)
        guard index == 0, shouldFail else { return }
        continuation.yield(.failure(try MeetingTranscriptionFailureEvent(
            context: MeetingTranscriptionEventContext(
                eventID: UUID(),
                operationID: packet.operationID,
                sessionID: context.sessionID,
                trackID: context.trackID,
                source: context.source,
                providerEpoch: packet.providerEpoch,
                sequenceNumber: Int64(packetCount),
                emittedAtMilliseconds: 2_000
            ),
            code: "disconnected",
            message: "Sanitized test failure",
            classification: .transient
        )))
    }

    func finish() async throws {
        continuation.finish()
    }

    func cancel() async {
        continuation.finish()
    }

    private var packetCount: Int {
        300
    }
}

private enum ReconnectScenario: Sendable {
    case disconnect
    case rateLimited
    case rotation
    case seam
    case outOfOrder
    case permanent
    case success
}

private actor ReconnectScript {
    let scenario: ReconnectScenario
    private var sessionCount = 0
    private var packets: [MeetingNormalizedAudioPacket] = []

    init(scenario: ReconnectScenario) {
        self.scenario = scenario
    }

    func nextSessionIndex() -> Int {
        defer { sessionCount += 1 }
        return sessionCount
    }

    func record(_ packet: MeetingNormalizedAudioPacket) {
        packets.append(packet)
    }

    func submissions() -> [MeetingNormalizedAudioPacket] {
        packets
    }

    func waitForSessionCount(_ count: Int) async {
        while sessionCount < count { await Task.yield() }
    }

    func waitForEpoch(_ epoch: Int) async {
        while !packets.contains(where: { $0.providerEpoch.rawValue == epoch }) { await Task.yield() }
    }
}

private final class ReconnectProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    let descriptor: MeetingTranscriptionProviderDescriptor
    private let script: ReconnectScript

    init(script: ReconnectScript) throws {
        descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
        self.script = script
    }

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        ReconnectSession(
            index: await script.nextSessionIndex(),
            context: try MeetingTrackTranscriptionContextSnapshot(
                sessionID: context.sessionID,
                trackID: context.trackID,
                source: context.source,
                canonicalSampleRateHertz: context.canonicalSampleRateHertz,
                channelCount: context.channelCount,
                startedAtMilliseconds: context.startedAtMilliseconds,
                keyterms: context.keyterms
            ),
            script: script
        )
    }
}

private actor ReconnectSession: MeetingTrackTranscriptionSession {
    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let index: Int
    private let context: MeetingTrackTranscriptionContextSnapshot
    private let script: ReconnectScript
    private let continuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation
    private var triggered = false

    init(index: Int, context: MeetingTrackTranscriptionContextSnapshot, script: ReconnectScript) {
        self.index = index
        self.context = context
        self.script = script
        var streamContinuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation!
        events = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func start() async throws {}

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        await script.record(packet)
        let scenario = script.scenario
        if index == 0 {
            try emitInitial(packet: packet, scenario: scenario)
            return
        }
        try emitReconnected(packet: packet, scenario: scenario)
    }

    func finish() async throws {
        continuation.finish()
    }

    func cancel() async {
        continuation.finish()
    }

    private func emitInitial(packet: MeetingNormalizedAudioPacket, scenario: ReconnectScenario) throws {
        guard !triggered || scenario == .seam || scenario == .outOfOrder else { return }
        switch scenario {
        case .disconnect:
            triggered = true
            continuation.yield(.failure(try failure(packet: packet, classification: .transient)))
        case .rateLimited:
            triggered = true
            continuation.yield(.failure(try failure(
                packet: packet,
                classification: .rateLimited,
                retryAfterMilliseconds: 750
            )))
        case .rotation:
            triggered = true
            continuation.yield(.warning(try MeetingTranscriptionWarningEvent(
                context: eventContext(packet: packet),
                code: "session-rotation-required",
                message: "Rotate",
                isRecoverable: true
            )))
        case .seam:
            if packet.sampleRange.startFrame == 0 {
                continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "first")))
            } else if !triggered {
                triggered = true
                continuation.yield(.failure(try failure(packet: packet, classification: .transient)))
            }
        case .outOfOrder:
            if packet.sampleRange.startFrame == 2 {
                continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "later")))
            } else if packet.sampleRange.startFrame == 4 {
                triggered = true
                continuation.yield(.failure(try failure(packet: packet, classification: .transient)))
            }
        case .permanent:
            triggered = true
            continuation.yield(.failure(try failure(packet: packet, classification: .permanent)))
        case .success:
            continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "local")))
        }
    }

    private func emitReconnected(packet: MeetingNormalizedAudioPacket, scenario: ReconnectScenario) throws {
        if scenario == .outOfOrder {
            continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "replayed")))
            return
        }
        guard scenario == .seam else {
            continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "reconnected")))
            return
        }
        if packet.sampleRange.startFrame == 0 {
            continuation.yield(.final(try final(packet: packet, id: UUID(), text: "duplicate")))
            return
        }
        continuation.yield(.final(try final(packet: packet, id: packet.operationID, text: "second")))
        let staleContext = try MeetingTranscriptionEventContext(
            eventID: UUID(),
            operationID: UUID(),
            sessionID: context.sessionID,
            trackID: context.trackID,
            source: context.source,
            providerEpoch: .initial,
            sequenceNumber: 99,
            emittedAtMilliseconds: 3_000
        )
        continuation.yield(.final(MeetingTranscriptionFinalEvent(
            context: staleContext,
            utterance: try MeetingTranscriptionUtterance(
                id: UUID(),
                revision: 0,
                sampleRange: packet.sampleRange,
                text: "stale",
                createdAtMilliseconds: 3_000
            )
        )))
    }

    private func failure(
        packet: MeetingNormalizedAudioPacket,
        classification: MeetingTranscriptionFailureClassification,
        retryAfterMilliseconds: Int64? = nil
    ) throws -> MeetingTranscriptionFailureEvent {
        try MeetingTranscriptionFailureEvent(
            context: eventContext(packet: packet),
            code: classification == .rateLimited ? "rate-limited" : "disconnected",
            message: "Sanitized test failure",
            classification: classification,
            retryAfterMilliseconds: retryAfterMilliseconds
        )
    }

    private func final(
        packet: MeetingNormalizedAudioPacket,
        id: UUID,
        text: String
    ) throws -> MeetingTranscriptionFinalEvent {
        MeetingTranscriptionFinalEvent(
            context: try eventContext(packet: packet),
            utterance: try MeetingTranscriptionUtterance(
                id: id,
                revision: 0,
                sampleRange: packet.sampleRange,
                text: text,
                createdAtMilliseconds: 2_000 + Int64(index)
            )
        )
    }

    private func eventContext(packet: MeetingNormalizedAudioPacket) throws -> MeetingTranscriptionEventContext {
        try MeetingTranscriptionEventContext(
            eventID: UUID(),
            operationID: packet.operationID,
            sessionID: packet.sessionID,
            trackID: packet.trackID,
            source: packet.source,
            providerEpoch: packet.providerEpoch,
            sequenceNumber: Int64(index),
            emittedAtMilliseconds: 2_000 + Int64(index)
        )
    }
}

private actor RetryDelayRecorder {
    private var recorded: [Int64] = []

    func record(_ value: Int64) {
        recorded.append(value)
    }

    func values() -> [Int64] {
        recorded
    }
}

private final class RouterTestProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    let descriptor: MeetingTranscriptionProviderDescriptor

    private let blockedTrackID: UUID?
    private let blockAll: Bool
    private let scripted: Bool
    private let lifecycle: RouterSessionLifecycleRecorder

    init(
        blockedTrackID: UUID? = nil,
        blockAll: Bool = false,
        scripted: Bool = false,
        lifecycle: RouterSessionLifecycleRecorder
    ) throws {
        descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
        self.blockedTrackID = blockedTrackID
        self.blockAll = blockAll
        self.scripted = scripted
        self.lifecycle = lifecycle
    }

    func readiness(for _: MeetingTranscriptionRoute) async -> MeetingTranscriptionReadiness {
        .ready
    }

    func makeSession(
        route _: MeetingTranscriptionRoute,
        context: any MeetingTrackTranscriptionContext
    ) async throws -> any MeetingTrackTranscriptionSession {
        RouterTestSession(
            trackID: context.trackID,
            blocks: blockAll || context.trackID == blockedTrackID,
            scripted: scripted,
            lifecycle: lifecycle
        )
    }
}

private actor RouterTestSession: MeetingTrackTranscriptionSession {
    nonisolated let events: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>

    private let trackID: UUID
    private let blocks: Bool
    private let scripted: Bool
    private let lifecycle: RouterSessionLifecycleRecorder
    private let continuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation

    init(trackID: UUID, blocks: Bool, scripted: Bool, lifecycle: RouterSessionLifecycleRecorder) {
        self.trackID = trackID
        self.blocks = blocks
        self.scripted = scripted
        self.lifecycle = lifecycle
        var streamContinuation: AsyncThrowingStream<MeetingTranscriptionProviderEvent, any Error>.Continuation!
        events = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func start() async throws {
        await lifecycle.recordStarted(trackID)
    }

    func submit(_ packet: MeetingNormalizedAudioPacket) async throws {
        if blocks {
            while !Task.isCancelled {
                await Task.yield()
            }
            throw CancellationError()
        }
        if scripted {
            try emitScript(packet)
        } else {
            continuation.yield(.final(MeetingTranscriptionFinalEvent(
                context: try eventContext(packet: packet, sequence: 0),
                utterance: try utterance(packet: packet, revision: 0, text: "active")
            )))
        }
    }

    func finish() async throws {
        await lifecycle.recordFinished(trackID)
        continuation.finish()
    }

    func cancel() async {
        await lifecycle.recordCancelled(trackID)
        continuation.finish()
    }

    private func emitScript(_ packet: MeetingNormalizedAudioPacket) throws {
        continuation.yield(.partial(MeetingTranscriptionPartialEvent(
            context: try eventContext(packet: packet, sequence: 0),
            utterance: try utterance(packet: packet, revision: 0, text: "draft")
        )))
        continuation.yield(.final(MeetingTranscriptionFinalEvent(
            context: try eventContext(packet: packet, sequence: 1),
            utterance: try utterance(packet: packet, revision: 1, text: "final")
        )))
        let warningContext = try eventContext(packet: packet, sequence: 2)
        continuation.yield(.warning(try MeetingTranscriptionWarningEvent(
            context: warningContext,
            code: "test-warning",
            message: "Warning",
            isRecoverable: true
        )))
        continuation.yield(.usage(try MeetingTranscriptionUsageEvent(
            context: try eventContext(packet: packet, sequence: 3),
            metrics: [MeetingTranscriptionUsageMetric(billingUnit: "seconds", quantity: 1)]
        )))
        continuation.yield(.rateLimit(try MeetingTranscriptionRateLimitEvent(
            context: try eventContext(packet: packet, sequence: 4),
            scope: "track"
        )))
        continuation.yield(.session(try MeetingTranscriptionSessionEvent(
            context: try eventContext(packet: packet, sequence: 5),
            state: .ready
        )))
    }

    private func eventContext(
        packet: MeetingNormalizedAudioPacket,
        sequence: Int64
    ) throws -> MeetingTranscriptionEventContext {
        try MeetingTranscriptionEventContext(
            eventID: sequence < 2 ? UUID(uuidString: String(format: "00000000-0000-0000-0000-%012lld", sequence + 1))! : UUID(),
            operationID: packet.operationID,
            sessionID: packet.sessionID,
            trackID: packet.trackID,
            source: packet.source,
            providerEpoch: packet.providerEpoch,
            sequenceNumber: sequence,
            emittedAtMilliseconds: 2_000 + sequence
        )
    }

    private func utterance(
        packet: MeetingNormalizedAudioPacket,
        revision: Int,
        text: String
    ) throws -> MeetingTranscriptionUtterance {
        try MeetingTranscriptionUtterance(
            id: packet.operationID,
            revision: revision,
            sampleRange: packet.sampleRange,
            text: text,
            createdAtMilliseconds: 2_000 + Int64(revision)
        )
    }
}

private actor RouterSessionLifecycleRecorder {
    private var started: [UUID] = []
    private var finished: [UUID] = []
    private var cancelled: [UUID] = []

    func recordStarted(_ trackID: UUID) {
        if !started.contains(trackID) {
            started.append(trackID)
        }
    }

    func recordFinished(_ trackID: UUID) {
        finished.append(trackID)
    }

    func recordCancelled(_ trackID: UUID) {
        if !cancelled.contains(trackID) {
            cancelled.append(trackID)
        }
    }

    func finishedTrackIDs() -> [UUID] {
        finished
    }

    func cancelledTrackIDs() -> [UUID] {
        cancelled
    }

    func waitForStarted(trackIDs: Set<UUID>) async {
        while !trackIDs.isSubset(of: Set(started)) { await Task.yield() }
    }
}

private actor RouterRuntimeEventRecorder {
    private var events: [MeetingTranscriptionRuntimeEvent] = []

    func record(_ event: MeetingTranscriptionRuntimeEvent) {
        events.append(event)
    }

    func waitForFinal(id: UUID) async {
        while !finalIDs().contains(id) {
            await Task.yield()
        }
    }

    func finalIDs() -> [UUID] {
        events.compactMap { event in
            guard case let .final(segment) = event else { return nil }
            return segment.id
        }
    }

    func segments() -> [MeetingTranscriptSegment] {
        events.compactMap { event in
            switch event {
            case let .partial(segment), let .final(segment):
                segment
            default:
                nil
            }
        }
    }

    func warningCount() -> Int {
        events.filter { if case .warning = $0 { true } else { false } }.count
    }

    func usageCount() -> Int {
        events.filter { if case .usage = $0 { true } else { false } }.count
    }

    func rateLimitCount() -> Int {
        events.filter { if case .rateLimit = $0 { true } else { false } }.count
    }

    func sessionCount() -> Int {
        events.filter { if case .session = $0 { true } else { false } }.count
    }

    func healthStates() -> [MeetingTranscriptionTrackRuntimeState] {
        events.compactMap { event in
            guard case let .health(health) = event else { return nil }
            return health.state
        }
    }

    func waitForHealth(_ state: MeetingTranscriptionTrackRuntimeState) async {
        while !healthStates().contains(state) { await Task.yield() }
    }

    func failureRanges() -> [MeetingCanonicalSampleRange] {
        events.compactMap { event in
            guard case let .failureRange(_, range) = event else { return nil }
            return range
        }
    }
}
