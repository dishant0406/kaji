import AVFoundation
import Foundation

enum SpeechAudioSampleRate {
    static let targetHz: Double = 16_000
}

final class SpeechAudioResampler: @unchecked Sendable {
    private var converters: [Double: AVAudioConverter] = [:]
    private let lock = NSLock()

    func convertTo16kMono(_ chunk: SpeechAudioChunk) -> SpeechAudioChunk? {
        guard chunk.sampleRate != SpeechAudioSampleRate.targetHz else { return chunk }
        guard let samples = convertedSamples(chunk) else { return nil }
        return SpeechAudioChunk(samples: samples, sampleRate: SpeechAudioSampleRate.targetHz)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        converters.removeAll()
    }

    private func convertedSamples(_ chunk: SpeechAudioChunk) -> [Float]? {
        guard let inputFormat = makeFormat(sampleRate: chunk.sampleRate),
              let inputBuffer = chunk.makeBuffer(format: inputFormat),
              let outputFormat = makeFormat(sampleRate: SpeechAudioSampleRate.targetHz),
              let converter = converter(for: chunk.sampleRate)
        else { return nil }
        converter.reset()

        var collected: [Float] = []
        var hasPendingInput = true
        var conversionError: NSError?

        var iterations = 0
        while iterations < 16 {
            iterations += 1
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 16_384) else {
                return nil
            }
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if hasPendingInput {
                    hasPendingInput = false
                    inputStatus.pointee = .haveData
                    return inputBuffer
                }
                inputStatus.pointee = .endOfStream
                return nil
            }
            if let channelData = outputBuffer.floatChannelData, outputBuffer.frameLength > 0 {
                collected.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        guard conversionError == nil, !collected.isEmpty else { return nil }
        return collected
    }

    private func makeFormat(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    private func converter(for sampleRate: Double) -> AVAudioConverter? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = converters[sampleRate] { return cached }
        guard let inputFormat = makeFormat(sampleRate: sampleRate),
              let outputFormat = makeFormat(sampleRate: SpeechAudioSampleRate.targetHz)
        else { return nil }
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        converters[sampleRate] = converter
        return converter
    }
}
