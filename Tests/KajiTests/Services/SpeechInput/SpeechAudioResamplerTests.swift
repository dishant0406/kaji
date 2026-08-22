import Foundation
import Testing

@testable import Kaji

@Suite("Speech audio resampler")
struct SpeechAudioResamplerTests {
    private func makeChunk(samples: [Float], sampleRate: Double) -> SpeechAudioChunk {
        SpeechAudioChunk(samples: samples, sampleRate: sampleRate)
    }

    @Test("48 kHz mono chunk is resampled to 16 kHz")
    func resamples48kMono() throws {
        let resampler = SpeechAudioResampler()
        let sourceRate = 48_000.0
        let samples: [Float] = (0 ..< 4_800).map { index in Float(sin(Double(index) * .pi / 180)) }
        let chunk = makeChunk(samples: samples, sampleRate: sourceRate)

        let converted = try #require(resampler.convertTo16kMono(chunk))
        #expect(converted.sampleRate == 16_000)
        #expect(abs(converted.samples.count - 1_600) <= 32)
    }

    @Test("16 kHz chunk passes through unchanged")
    func passthroughAtTargetRate() {
        let resampler = SpeechAudioResampler()
        let chunk = makeChunk(samples: [0.1, 0.2, 0.3], sampleRate: 16_000)
        let converted = resampler.convertTo16kMono(chunk)
        #expect(converted?.samples == [0.1, 0.2, 0.3])
        #expect(converted?.sampleRate == 16_000)
    }

    @Test("resampled output keeps waveform shape within tolerance")
    func waveformShapeIsPreserved() throws {
        let resampler = SpeechAudioResampler()
        let sourceRate = 48_000.0
        let frames = 4_800
        let samples: [Float] = (0 ..< frames).map { index in
            Float(sin(2 * .pi * 220 * Double(index) / sourceRate))
        }
        let chunk = makeChunk(samples: samples, sampleRate: sourceRate)

        let converted = try #require(resampler.convertTo16kMono(chunk))
        let peak = converted.samples.map(abs).max() ?? 0
        #expect(peak > 0.9)
    }

    @Test("repeated conversions reuse cached converter state cleanly")
    func repeatedConversionsAreIndependent() throws {
        let resampler = SpeechAudioResampler()
        let first = try #require(resampler.convertTo16kMono(makeChunk(samples: Array(repeating: 0.5, count: 4_800), sampleRate: 44_100)))
        let second = try #require(resampler.convertTo16kMono(makeChunk(samples: Array(repeating: -0.5, count: 4_800), sampleRate: 44_100)))
        #expect(first.sampleRate == 16_000)
        #expect(second.sampleRate == 16_000)
        let secondMean = second.samples.reduce(0, +) / Float(max(1, second.samples.count))
        #expect(secondMean < 0)
    }
}
