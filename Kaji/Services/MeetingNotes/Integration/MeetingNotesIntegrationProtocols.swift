import Foundation
@preconcurrency import ScreenCaptureKit

struct MeetingRecordingConsent: Equatable {
    let id: UUID
    let configuration: MeetingSessionConfiguration
}

@MainActor
protocol MeetingClock: AnyObject {
    func nowMilliseconds() -> Int64
    func sleep(forMilliseconds milliseconds: Int64) async throws
}

@MainActor
final class SystemMeetingClock: MeetingClock {
    func nowMilliseconds() -> Int64 {
        max(0, Int64(Date().timeIntervalSince1970 * 1000))
    }

    func sleep(forMilliseconds milliseconds: Int64) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

protocol MeetingSessionPersisting: Actor {
    func save(_ document: MeetingSessionDocument) throws
    func load() throws -> MeetingLoadResult
    func recoverStaleSessions(
        nowMilliseconds: Int64,
        staleAfterMilliseconds: Int64,
        reason: String
    ) throws -> [UUID]
    func deleteSession(id: UUID, includingPinned: Bool) throws -> Bool
    func finalize(_ document: MeetingSessionDocument, settings: MeetingNotesSettings) throws -> MeetingSessionDocument
    func finalizeAndEnforceRetention(
        _ document: MeetingSessionDocument,
        settings: MeetingNotesSettings,
        nowMilliseconds: Int64
    ) throws -> MeetingFinalizationResult
    func enforceRetention(settings: MeetingNotesSettings, nowMilliseconds: Int64) throws -> MeetingRetentionResult
}

extension MeetingSessionPersisting {
    func finalizeAndEnforceRetention(
        _ document: MeetingSessionDocument,
        settings: MeetingNotesSettings,
        nowMilliseconds: Int64
    ) throws -> MeetingFinalizationResult {
        let finalized = try finalize(document, settings: settings)
        let retention = try enforceRetention(settings: settings, nowMilliseconds: nowMilliseconds)
        return MeetingFinalizationResult(document: finalized, retention: retention)
    }
}

extension MeetingSessionStore: MeetingSessionPersisting {}

@MainActor
protocol MeetingContentPicking: AnyObject {
    var isActive: Bool { get }
    func selectApplication() async throws -> MeetingContentSelection
    func cancel()
}

@MainActor
final class MeetingContentSelection {
    let filter: SCContentFilter?

    init(filter: SCContentFilter) {
        self.filter = filter
    }

    init() {
        filter = nil
    }
}

protocol MeetingAudioIngress: Sendable {
    func finish() async
    func cancel() async
}

extension MeetingAudioQueueIngress: MeetingAudioIngress {}

protocol MeetingAudioPipelineSession: Actor {
    func start() async
    func waitUntilFinished() async
    func waitUntilFinished(timeout: Duration) async -> MeetingAudioPipelineDrainResult
    func cancel() async
}

extension MeetingAudioPipelineSession {
    func waitUntilFinished(timeout _: Duration) async -> MeetingAudioPipelineDrainResult {
        await waitUntilFinished()
        return .finished
    }
}

extension MeetingAudioProcessingPipeline: MeetingAudioPipelineSession {}

@MainActor
struct MeetingRecordingRuntime {
    let ingress: any MeetingAudioIngress
    let pipeline: any MeetingAudioPipelineSession
    let capture: any MeetingAudioCaptureSession
}

struct MeetingRecordingSources {
    let systemAudio: MeetingAudioSourceIdentity?
    let microphone: MeetingAudioSourceIdentity?
}

@MainActor
protocol MeetingRecordingRuntimeBuilding: AnyObject {
    func makeRuntime(
        selection: MeetingContentSelection,
        sessionID: UUID,
        transcription: MeetingResolvedTranscriptionProvider,
        sources: MeetingRecordingSources,
        eventHandler: @escaping MeetingAudioProcessingPipeline.EventHandler
    ) throws -> MeetingRecordingRuntime
}

@MainActor
protocol MeetingTranscriptionProviderResolving: AnyObject {
    func resolve(configuration: MeetingSessionConfiguration) throws -> MeetingResolvedTranscriptionProvider
}

extension MeetingTranscriptionProviderCatalog: MeetingTranscriptionProviderResolving {}

@MainActor
final class DefaultMeetingRecordingRuntimeFactory: MeetingRecordingRuntimeBuilding {
    func makeRuntime(
        selection: MeetingContentSelection,
        sessionID: UUID,
        transcription: MeetingResolvedTranscriptionProvider,
        sources: MeetingRecordingSources,
        eventHandler: @escaping MeetingAudioProcessingPipeline.EventHandler
    ) throws -> MeetingRecordingRuntime {
        guard let filter = selection.filter else { throw MeetingAudioError.invalidAudioFormat }
        let queue = try MeetingAudioEventQueue(audioCapacity: 256)
        let ingress = MeetingAudioQueueIngress(queue: queue)
        let router = try MeetingTranscriptionRuntimeRouter(
            provider: transcription.provider,
            route: transcription.route,
            fallback: transcription.localFallback.map {
                MeetingTranscriptionRuntimeFallback(provider: $0.provider, route: $0.route)
            }
        ) { event in
            switch event {
            case let .partial(segment):
                await eventHandler(.partialTranscript(segment))
            case let .final(segment):
                await eventHandler(.transcript(segment))
            case let .committedMetadata(metadata):
                await eventHandler(.committedMetadata(metadata))
            case let .metadataAmendment(metadata):
                await eventHandler(.metadataAmendment(metadata))
            case let .failure(failure):
                await eventHandler(.transcriptionFailure(failure))
            case let .failureRange(failure, range):
                await eventHandler(.transcriptionFailureRange(failure, range))
            case let .usage(usage):
                await eventHandler(.transcriptionUsage(usage))
            case let .rateLimit(rateLimit):
                await eventHandler(.transcriptionRateLimit(rateLimit))
            case let .warning(warning):
                await eventHandler(.transcriptionWarning(warning))
            case let .session(session):
                await eventHandler(.transcriptionSession(session))
            case let .health(health):
                await eventHandler(.transcriptionTrackHealth(health))
            }
        }
        let pipeline = try MeetingAudioProcessingPipeline(
            queue: queue,
            configuration: MeetingAudioChunkConfiguration(),
            transcriptionRouter: router,
            transcriptionSessionID: sessionID,
            transcriptionMode: transcription.route.mode,
            keyterms: transcription.keyterms,
            eventHandler: eventHandler
        )
        let capture = try ScreenCaptureMeetingAudioCapture(
            filter: filter,
            microphoneCaptureDeviceID: nil,
            systemAudioSource: sources.systemAudio,
            microphoneSource: sources.microphone,
            ingress: ingress
        )
        return MeetingRecordingRuntime(ingress: ingress, pipeline: pipeline, capture: capture)
    }
}
