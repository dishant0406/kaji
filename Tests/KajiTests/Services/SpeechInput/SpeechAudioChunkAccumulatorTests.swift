@preconcurrency import AVFoundation
import Testing

@testable import Kaji

@Suite("Speech audio chunk accumulator")
struct SpeechAudioChunkAccumulatorTests {
    private func makeBuffer(samples: [Float], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData?[0][index] = sample
        }
        return buffer
    }

    @Test("appended samples accumulate until a snapshot clears them")
    func accumulateThenSnapshot() throws {
        let accumulator = SpeechAudioChunkAccumulator()
        accumulator.append(try makeBuffer(samples: [0.1, 0.2, 0.3]))
        let first = try #require(accumulator.snapshotChunk())
        #expect(first.samples == [0.1, 0.2, 0.3])
        #expect(first.sampleRate == 16_000)

        #expect(accumulator.snapshotChunk() == nil)

        accumulator.append(try makeBuffer(samples: [0.4, 0.5]))
        let second = try #require(accumulator.snapshotChunk())
        #expect(second.samples == [0.4, 0.5])
    }

    @Test("parallel appends do not interleave sample data")
    func parallelAppendsAreIsolated() async throws {
        let accumulator = SpeechAudioChunkAccumulator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<100 {
                        accumulator.append((try? self.makeBuffer(samples: [0.5]))!)
                    }
                }
            }
        }
        let chunk = try #require(accumulator.finishChunk())
        #expect(chunk.samples.count == 400)
        #expect(chunk.samples.allSatisfy { $0 == 0.5 })
    }

    @Test("finishChunk returns remaining samples then clears")
    func finishChunkReturnsAndClears() throws {
        let accumulator = SpeechAudioChunkAccumulator()
        accumulator.append(try makeBuffer(samples: [0.1, 0.2]))
        let chunk = try #require(accumulator.finishChunk())
        #expect(chunk.samples == [0.1, 0.2])
        #expect(accumulator.finishChunk() == nil)
    }

    @Test("empty accumulator yields no chunk")
    func emptyAccumulatorYieldsNil() {
        let accumulator = SpeechAudioChunkAccumulator()
        #expect(accumulator.snapshotChunk() == nil)
        #expect(accumulator.finishChunk() == nil)
    }
}
