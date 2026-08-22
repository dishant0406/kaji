@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import Kaji

@Suite("Speech audio chunk")
struct SpeechAudioChunkOverlapTests {
    private func makeBuffer(samples: [Float], sampleRate: Double = 16_000, channels: AVAudioChannelCount = 1) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData?[0][index] = sample
        }
        return buffer
    }

    @Test("suffixSamples returns the requested duration at the chunk rate")
    func suffixSamplesDuration() {
        let chunk = SpeechAudioChunk(samples: Array(repeating: 0.5, count: 32_000), sampleRate: 16_000)
        let tail = chunk.suffixSamples(seconds: 1.25)
        #expect(tail.samples.count == 20_000)
    }

    @Test("suffixSamples clamps to available samples")
    func suffixSamplesClamps() {
        let chunk = SpeechAudioChunk(samples: [0.1, 0.2, 0.3], sampleRate: 16_000)
        let tail = chunk.suffixSamples(seconds: 10)
        #expect(tail.samples == [0.1, 0.2, 0.3])
    }

    @Test("appending concatenates samples at the same rate")
    func appendingConcatenates() {
        let first = SpeechAudioChunk(samples: [0.1], sampleRate: 16_000)
        let second = SpeechAudioChunk(samples: [0.2], sampleRate: 16_000)
        let combined = first.appending(second)
        #expect(combined.samples == [0.1, 0.2])
        #expect(combined.sampleRate == 16_000)
    }

    @Test("duration reflects rate and frame count")
    func durationMatchesRate() {
        let chunk = SpeechAudioChunk(samples: Array(repeating: 0, count: 32_000), sampleRate: 16_000)
        #expect(chunk.durationSeconds == 2.0)
    }

    @Test("stereo buffer is downmixed to averaged mono samples")
    func stereoDownmix() throws {
        let frames = 4_410
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0 ..< frames {
            buffer.floatChannelData?[0][frame] = 0.5
            buffer.floatChannelData?[1][frame] = -0.5
        }
        let chunk = try #require(SpeechAudioChunk.make(from: buffer))
        #expect(chunk.samples.count == frames)
        let mean = chunk.samples.reduce(0, +) / Float(frames)
        #expect(abs(mean) < 0.001)
    }
}
