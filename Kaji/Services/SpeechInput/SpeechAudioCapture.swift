@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechAudioCapture: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isCapturing = false

    func start(session: SpeechCaptureSession) throws {
        guard !isCapturing else { return }
        guard Self.hasMicrophoneAccess else { throw SpeechInputError.microphonePermissionDenied }
        let url = Self.recordingURL(for: session)
        let next = try AVAudioRecorder(url: url, settings: Self.recorderSettings)
        next.delegate = self
        next.isMeteringEnabled = false
        guard next.prepareToRecord(), next.record() else {
            throw SpeechInputError.audioInputUnavailable
        }
        recorder = next
        recordingURL = url
        isCapturing = true
    }

    func stop(session _: SpeechCaptureSession?, reason _: SpeechCaptureStopReason) -> [SpeechAudioChunk] {
        guard isCapturing else { return [] }
        isCapturing = false
        let current = recorder
        let url = recordingURL
        recorder = nil
        recordingURL = nil
        current?.stop()
        let result = loadRecording(url: url)
        try? url.map { try FileManager.default.removeItem(at: $0) }
        return result.chunks
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_: AVAudioRecorder, error: Error?) {
        guard let error else { return }
        DebugFileLog.logError("SpeechInput", error, context: "capture recorder encode failed")
    }

    private func loadRecording(url: URL?) -> SpeechAudioCaptureResult {
        guard let url else { return .empty }
        do {
            let file = try AVAudioFile(forReading: url)
            let frames = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                return .empty
            }
            try file.read(into: buffer)
            guard let chunk = SpeechAudioChunk.make(from: buffer) else { return .empty }
            return SpeechAudioCaptureResult(chunks: [chunk], droppedCount: 0, frameCount: chunk.frameCount)
        } catch {
            DebugFileLog.logError("SpeechInput", error, context: "capture recording read failed")
            return .empty
        }
    }

    private static var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private static func recordingURL(for session: SpeechCaptureSession) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KajiSpeech-\(session.logID)-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }

    static var hasMicrophoneAccess: Bool {
        SpeechMicrophonePermissionState.current == .allowed
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
