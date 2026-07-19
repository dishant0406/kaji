import Foundation
import Testing

@testable import Kaji

@Suite("STT audio encoding")
struct STTAudioEncodingTests {
    @Test("PCM conversion clips and writes little-endian signed samples")
    func pcmClipping() throws {
        let encoded = try STTPCM16LittleEndianEncoder.encode(
            samples: [-2, -1, -0.5, 0, 0.5, 1, 2],
            sampleRate: .hertz16000,
            maximumFrames: 7
        )

        #expect(int16Values(encoded) == [.min, .min, -16_384, 0, 16_384, .max, .max])
    }

    @Test("PCM encoder supports only bounded 16k and 24k frames")
    func boundedFrames() throws {
        var encoder = try STTBoundedPCM16FrameEncoder(
            sampleRate: .hertz24000,
            maximumFramesPerChunk: 2,
            maximumTotalFrames: 3
        )

        #expect(try encoder.encode([0, 0]).count == 4)
        #expect(throws: STTAudioEncodingError.sizeLimitExceeded) {
            try encoder.encode([0, 0])
        }
        #expect(throws: STTAudioEncodingError.invalidSamples) {
            try STTPCM16LittleEndianEncoder.encode(
                samples: [.nan],
                sampleRate: .hertz16000,
                maximumFrames: 1
            )
        }
    }

    @Test("WAV output has canonical PCM16 mono header")
    func wavHeader() throws {
        let pcm = try STTPCM16LittleEndianEncoder.encode(
            samples: [-1, 0, 1],
            sampleRate: .hertz16000,
            maximumFrames: 3
        )
        let wav = try STTMultipartWAVEncoder.wav(pcm16: pcm, sampleRate: .hertz16000)

        #expect(String(data: wav[0 ..< 4], encoding: .ascii) == "RIFF")
        #expect(uint32(wav, at: 4) == 42)
        #expect(String(data: wav[8 ..< 12], encoding: .ascii) == "WAVE")
        #expect(uint16(wav, at: 20) == 1)
        #expect(uint16(wav, at: 22) == 1)
        #expect(uint32(wav, at: 24) == 16_000)
        #expect(uint32(wav, at: 28) == 32_000)
        #expect(uint16(wav, at: 32) == 2)
        #expect(uint16(wav, at: 34) == 16)
        #expect(String(data: wav[36 ..< 40], encoding: .ascii) == "data")
        #expect(uint32(wav, at: 40) == 6)
        #expect(wav.suffix(6) == pcm)
    }

    @Test("multipart encoding rejects header injection and hard limits")
    func multipartSafety() throws {
        let wav = try STTMultipartWAVEncoder.wav(pcm16: Data([0, 0]), sampleRate: .hertz16000)
        let body = try STTMultipartWAVEncoder.multipart(
            wav: wav,
            filename: "audio.wav",
            boundary: "safe-boundary"
        )
        #expect(String(decoding: body, as: UTF8.self).contains("filename=\"audio.wav\""))
        #expect(throws: STTAudioEncodingError.invalidMultipartValue) {
            try STTMultipartWAVEncoder.multipart(
                wav: wav,
                filename: "audio.wav\r\nX-API-Key: secret",
                boundary: "safe-boundary"
            )
        }
        #expect(throws: STTAudioEncodingError.sizeLimitExceeded) {
            try STTMultipartWAVEncoder.multipart(
                wav: wav,
                filename: "audio.wav",
                boundary: "safe-boundary",
                maximumBytes: wav.count
            )
        }
    }

    private func int16Values(_ data: Data) -> [Int16] {
        stride(from: 0, to: data.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
        }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}
