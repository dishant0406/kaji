@preconcurrency import AVFoundation
import Testing
import Foundation

@testable import Kaji

@Suite("Speech audio capture tap handler")
struct SpeechAudioCaptureTapHandlerTests {
    private func makeBuffer(samples: [Float], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData?[0][index] = sample
        }
        return buffer
    }

    @Test("tap handler appends to accumulator from a non-main thread")
    func tapHandlerAppendsFromBackgroundThread() async throws {
        let accumulator = SpeechAudioChunkAccumulator()
        let handler = SpeechAudioCapture.tapHandler(for: accumulator)
        let buffer = try makeBuffer(samples: [0.1, 0.2, 0.3])

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                handler(buffer, AVAudioTime())
                continuation.resume()
            }
        }

        let chunk = try #require(accumulator.finishChunk())
        #expect(chunk.samples == [0.1, 0.2, 0.3])
        #expect(chunk.sampleRate == 16_000)
    }

    @Test("tap handler accumulates multiple invocations across threads")
    func tapHandlerAppendsAcrossThreads() async throws {
        let accumulator = SpeechAudioChunkAccumulator()
        let handler = SpeechAudioCapture.tapHandler(for: accumulator)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let buffer = (try? self.makeBuffer(samples: [0.25]))!
                    handler(buffer, AVAudioTime())
                }
            }
        }

        let chunk = try #require(accumulator.finishChunk())
        #expect(chunk.samples.count == 8)
        #expect(chunk.samples.allSatisfy { $0 == 0.25 })
    }
}
