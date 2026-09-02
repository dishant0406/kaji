@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechAudioCapture: NSObject, SpeechCapturing {
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isCapturing = false
    private var chunkAccumulator = SpeechAudioChunkAccumulator()
    private let resampler = SpeechAudioResampler()

    override init() {
        super.init()
    }

    func start(session: SpeechCaptureSession) throws {
        guard !isCapturing else { return }
        guard Self.hasMicrophoneAccess else { throw SpeechInputError.microphonePermissionDenied }
        let accumulator = SpeechAudioChunkAccumulator()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format,
            block: Self.tapHandler(for: accumulator)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechInputError.audioInputUnavailable
        }
        self.engine = engine
        self.inputNode = input
        chunkAccumulator = accumulator
        isCapturing = true
    }

    func snapshotChunk() -> SpeechAudioChunk? {
        guard isCapturing else { return nil }
        guard let chunk = normalized(chunkAccumulator.snapshotChunk()) else { return nil }
        let overlap = overlapTail
        overlapTail = chunk.suffixSamples(seconds: SpeechInputTiming.chunkOverlapSeconds)
        return chunk.appending(overlap ?? chunk.suffixSamples(seconds: 0))
    }

    func finish(session _: SpeechCaptureSession?, reason _: SpeechCaptureStopReason) -> SpeechAudioChunk? {
        stopEngine()
        let chunk = normalized(chunkAccumulator.finishChunk())
        chunkAccumulator = SpeechAudioChunkAccumulator()
        overlapTail = nil
        return chunk
    }

    private var overlapTail: SpeechAudioChunk?

    private func normalized(_ chunk: SpeechAudioChunk?) -> SpeechAudioChunk? {
        guard let chunk, !chunk.samples.isEmpty else { return nil }
        return resampler.convertTo16kMono(chunk)
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

    nonisolated static func tapHandler(
        for accumulator: SpeechAudioChunkAccumulator
    ) -> @Sendable @convention(block) (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            accumulator.append(buffer)
        }
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
        samples.removeAll(keepingCapacity: true)
        sampleRate = 0
        return chunk
    }

    func finishChunk() -> SpeechAudioChunk? {
        snapshotChunk()
    }
}
