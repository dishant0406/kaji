import Foundation
import Testing

@testable import Kaji

@Suite("OpenAI PCM16 audio conversion")
struct OpenAIPCM16AudioRateConverterTests {
    @Test("16 kHz PCM16 is deterministically resampled to 24 kHz")
    func resamples16kTo24k() throws {
        let input = [Int16](repeating: 12_345, count: 160)
        let packet = try MeetingNormalizedAudioPacket(
            operationID: UUID(),
            sessionID: UUID(),
            trackID: UUID(),
            source: .microphone,
            sampleRange: MeetingCanonicalSampleRange(startFrame: 0, endFrame: 160, sampleRateHertz: 16_000),
            encoding: .pcmSigned16LittleEndian,
            sampleRateHertz: 16_000,
            channelCount: 1,
            bytes: input.map(\.littleEndian).withUnsafeBytes { Data($0) },
            providerEpoch: .initial
        )

        let output = try OpenAIPCM16AudioRateConverter().pcm16Mono24kHz(from: packet)
        let samples = output.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 2).map {
                Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: Int16.self))
            }
        }

        #expect(samples.count == 240)
        #expect(Set(samples) == [12_345])
        #expect(try OpenAIPCM16AudioRateConverter().pcm16Mono24kHz(from: packet) == output)
    }

    @Test("realtime packetizer emits bounded PCM16 frames with canonical ranges")
    func realtimePacketization() throws {
        let source = try MeetingAudioTestFixtures.source()
        var packetizer = try MeetingRealtimeAudioPacketizer(source: source, frameMilliseconds: 100)
        let chunks = try packetizer.append(MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: 0,
            samples: [Float](repeating: 0.5, count: 3_200)
        ))
        let sessionID = UUID()
        let packets = try chunks.map { try $0.normalizedPacket(sessionID: sessionID, mode: .cloudRealtime) }

        #expect(packets.count == 2)
        #expect(packets.allSatisfy { $0.encoding == .pcmSigned16LittleEndian })
        #expect(packets.allSatisfy { $0.sampleRateHertz == 16_000 && $0.sampleRange.frameCount == 1_600 })
        #expect(packets.map(\.sampleRange.startFrame) == [0, 1_600])
        #expect(packets[0].operationID != packets[1].operationID)
    }
}
