@preconcurrency import AVFoundation
import Testing

@testable import Kaji

@Suite("Speech audio chunks")
struct SpeechAudioChunkTests {
    @Test("float buffer is copied into a sendable mono chunk")
    func floatBufferCopy() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        buffer.floatChannelData?[0][0] = 0.25
        buffer.floatChannelData?[0][1] = -0.5
        buffer.floatChannelData?[0][2] = 0.75
        let chunk = try #require(SpeechAudioChunk.make(from: buffer))
        buffer.floatChannelData?[0][0] = 1
        #expect(chunk.sampleRate == 16_000)
        #expect(chunk.samples == [0.25, -0.5, 0.75])
    }

    @Test("chunk rebuilds an audio buffer")
    func bufferRebuild() throws {
        let chunk = SpeechAudioChunk(samples: [0.1, 0.2], sampleRate: 16_000)
        let buffer = try #require(chunk.makeBuffer())
        #expect(buffer.frameLength == 2)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.floatChannelData?[0][0] == 0.1)
        #expect(buffer.floatChannelData?[0][1] == 0.2)
    }
}
