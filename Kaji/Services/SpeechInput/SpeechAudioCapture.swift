@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechAudioCapture: NSObject, SpeechCapturing {
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isCapturing = false
    private var chunkAccumulator: SpeechAudioChunkAccumulator

    override init() {
        chunkAccumulator = SpeechAudioChunkAccumulator()
        super.init()
    }

    func start(session: SpeechCaptureSession) throws {
        guard !isCapturing else { return }
        guard Self.hasMicrophoneAccess else { throw SpeechInputError.microphonePermissionDenied }
        let accumulator = SpeechAudioChunkAccumulator()
        chunkAccumulator = accumulator
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            accumulator.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechInputError.audioInputUnavailable
        }
        self.engine = engine
        self.inputNode = input
        isCapturing = true
    }

    func snapshotChunk() -> SpeechAudioChunk? {
        guard isCapturing else { return nil }
        return chunkAccumulator.snapshotChunk()
    }

    func finish(session _: SpeechCaptureSession?, reason _: SpeechCaptureStopReason) -> SpeechAudioChunk? {
        stopEngine()
        let chunk = chunkAccumulator.finishChunk()
        chunkAccumulator = SpeechAudioChunkAccumulator()
        return chunk
    }

    func stop(session: SpeechCaptureSession?, reason: SpeechCaptureStopReason) -> [SpeechAudioChunk] {
        let chunk = finish(session: session, reason: reason)
        guard let chunk, chunk.frameCount > 0 else { return [] }
        return [chunk]
    }

    private func stopEngine() {
        let input = inputNode
        if let engine, let input, engine.isRunning {
            input.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputNode = nil
        isCapturing = false
    }

    static var hasMicrophoneAccess: Bool {
        SpeechMicrophonePermissionState.current == .allowed
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

final class SpeechAudioChunkAccumulator: @unchecked Sendable {
    private let samplesLock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 0

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let chunk = SpeechAudioChunk.make(from: buffer) else { return }
        samplesLock.lock()
        if samples.isEmpty { sampleRate = chunk.sampleRate }
        samples.append(contentsOf: chunk.samples)
        samplesLock.unlock()
    }

    func snapshotChunk() -> SpeechAudioChunk? {
        samplesLock.lock()
        defer { samplesLock.unlock() }
        guard !samples.isEmpty else { return nil }
        let chunk = SpeechAudioChunk(samples: samples, sampleRate: sampleRate)
        samples = []
        return chunk
    }

    func finishChunk() -> SpeechAudioChunk? {
        snapshotChunk()
    }
}
