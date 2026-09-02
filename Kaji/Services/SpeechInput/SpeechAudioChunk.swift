@preconcurrency import AVFoundation
import Foundation

struct SpeechAudioChunk {
    let samples: [Float]
    let sampleRate: Double

    var frameCount: Int { samples.count }
    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    static func make(from buffer: AVAudioPCMBuffer) -> SpeechAudioChunk? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, buffer.format.sampleRate > 0 else { return nil }
        if let data = buffer.floatChannelData {
            return SpeechAudioChunk(
                samples: mixFloat(data, frames: frames, channels: channels, interleaved: buffer.format.isInterleaved),
                sampleRate: buffer.format.sampleRate
            )
        }
        if let data = buffer.int16ChannelData {
            return SpeechAudioChunk(
                samples: mixInt16(data, frames: frames, channels: channels, interleaved: buffer.format.isInterleaved),
                sampleRate: buffer.format.sampleRate
            )
        }
        return nil
    }

    func makeBuffer(format: AVAudioFormat? = nil) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        let resolvedFormat: AVAudioFormat
        if let format {
            resolvedFormat = format
        } else if let defaultFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) {
            resolvedFormat = defaultFormat
        } else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: resolvedFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return buffer
    }

    func appending(_ other: SpeechAudioChunk) -> SpeechAudioChunk {
        SpeechAudioChunk(samples: samples + other.samples, sampleRate: sampleRate)
    }

    func suffixSamples(seconds: Double) -> SpeechAudioChunk {
        let rate = max(1, Int(sampleRate))
        let count = min(samples.count, max(0, Int((seconds * Double(rate)).rounded())))
        return SpeechAudioChunk(samples: Array(samples.suffix(count)), sampleRate: sampleRate)
    }

    private static func mixFloat(
        _ data: UnsafePointer<UnsafeMutablePointer<Float>>,
        frames: Int,
        channels: Int,
        interleaved: Bool
    ) -> [Float] {
        if channels == 1 { return Array(UnsafeBufferPointer(start: data[0], count: frames)) }
        return (0 ..< frames).map { frame in
            let sum = (0 ..< channels).reduce(Float(0)) { partial, channel in
                partial + (interleaved ? data[0][frame * channels + channel] : data[channel][frame])
            }
            return sum / Float(channels)
        }
    }

    private static func mixInt16(
        _ data: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frames: Int,
        channels: Int,
        interleaved: Bool
    ) -> [Float] {
        (0 ..< frames).map { frame in
            let sum = (0 ..< channels).reduce(Float(0)) { partial, channel in
                let sample = interleaved ? data[0][frame * channels + channel] : data[channel][frame]
                return partial + Float(sample) / Float(Int16.max)
            }
            return sum / Float(channels)
        }
    }
}
