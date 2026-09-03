@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import os

struct MeetingSampleBufferAudioCopier {
    func copy(
        _ sampleBuffer: CMSampleBuffer,
        source: MeetingAudioSourceIdentity,
        sequenceNumber: Int64,
        capturedAtMilliseconds: Int64
    ) throws -> MeetingOwnedAudioBuffer {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription)
        else {
            throw MeetingAudioError.invalidBuffer
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            throw MeetingAudioError.invalidBuffer
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { throw MeetingAudioError.invalidBuffer }
        return try copy(
            buffer,
            source: source,
            sequenceNumber: sequenceNumber,
            capturedAtMilliseconds: capturedAtMilliseconds,
            presentationTimeNanoseconds: presentationTimeNanoseconds(sampleBuffer)
        )
    }

    func copy(
        _ buffer: AVAudioPCMBuffer,
        source: MeetingAudioSourceIdentity,
        sequenceNumber: Int64,
        capturedAtMilliseconds: Int64,
        presentationTimeNanoseconds: Int64? = nil
    ) throws -> MeetingOwnedAudioBuffer {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { throw MeetingAudioError.invalidBuffer }
        let samples = try interleavedSamples(
            from: buffer,
            frameCount: frameCount,
            channelCount: channelCount
        )
        return try MeetingOwnedAudioBuffer(
            source: source,
            sequenceNumber: sequenceNumber,
            capturedAtMilliseconds: capturedAtMilliseconds,
            presentationTimeNanoseconds: presentationTimeNanoseconds,
            sampleRate: buffer.format.sampleRate,
            channelCount: channelCount,
            interleavedSamples: samples
        )
    }

    private func interleavedSamples(
        from buffer: AVAudioPCMBuffer,
        frameCount: Int,
        channelCount: Int
    ) throws -> [Float] {
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else { throw MeetingAudioError.invalidBuffer }
            return interleave(
                channels,
                frameCount: frameCount,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                transform: { $0 }
            )
        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else { throw MeetingAudioError.invalidBuffer }
            return interleave(
                channels,
                frameCount: frameCount,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                transform: { Float($0) / Float(Int16.max) }
            )
        case .pcmFormatInt32:
            guard let channels = buffer.int32ChannelData else { throw MeetingAudioError.invalidBuffer }
            return interleave(
                channels,
                frameCount: frameCount,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                transform: { Float($0) / Float(Int32.max) }
            )
        default:
            throw MeetingAudioError.invalidAudioFormat
        }
    }

    private func interleave<Value>(
        _ channels: UnsafePointer<UnsafeMutablePointer<Value>>,
        frameCount: Int,
        channelCount: Int,
        isInterleaved: Bool,
        transform: (Value) -> Float
    ) -> [Float] {
        var output = [Float](repeating: 0, count: frameCount * channelCount)
        for frame in 0 ..< frameCount {
            for channel in 0 ..< channelCount {
                let input = isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                output[frame * channelCount + channel] = transform(input)
            }
        }
        return output
    }

    private func presentationTimeNanoseconds(_ sampleBuffer: CMSampleBuffer) -> Int64? {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, !timestamp.isIndefinite else { return nil }
        return CMTimeConvertScale(timestamp, timescale: 1_000_000_000, method: .default).value
    }
}

final class MeetingAudioResampler {
    private struct ConverterKey: Equatable {
        let sampleRate: Double
        let channelCount: Int
    }

    private struct ConverterState {
        let key: ConverterKey
        let inputFormat: AVAudioFormat
        let outputFormat: AVAudioFormat
        let converter: AVAudioConverter
        var lastSequenceNumber: Int64
        var totalInputFrames: Int64
        var emittedFrames: Int64
    }

    private var states: [MeetingAudioSourceIdentity: ConverterState] = [:]

    func convert(_ buffer: MeetingOwnedAudioBuffer) throws -> MeetingResampledAudioBuffer {
        if buffer.sampleRate == Double(MeetingAudioFormat.sampleRateHertz), buffer.channelCount == 1 {
            return MeetingResampledAudioBuffer(
                source: buffer.source,
                sequenceNumber: buffer.sequenceNumber,
                samples: buffer.interleavedSamples
            )
        }
        var state = try state(for: buffer)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: state.inputFormat,
            frameCapacity: AVAudioFrameCount(buffer.frameCount)
        ), let inputData = inputBuffer.floatChannelData?[0]
        else {
            throw MeetingAudioError.invalidBuffer
        }
        inputBuffer.frameLength = AVAudioFrameCount(buffer.frameCount)
        buffer.interleavedSamples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return }
            inputData.update(from: baseAddress, count: samples.count)
        }
        let ratio = state.outputFormat.sampleRate / state.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameCount) * ratio).rounded(.up)) + 256
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: state.outputFormat, frameCapacity: capacity) else {
            throw MeetingAudioError.invalidBuffer
        }
        let provided = OSAllocatedUnfairLock(initialState: false)
        nonisolated(unsafe) let capturedInput = inputBuffer
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            let alreadyProvided = provided.withLock { state -> Bool in
                if state {
                    return true
                }
                state = true
                return false
            }
            guard !alreadyProvided else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return capturedInput
        }
        var conversionError: NSError?
        let status = state.converter.convert(
            to: outputBuffer,
            error: &conversionError,
            withInputFrom: inputBlock
        )
        guard status != .error,
              conversionError == nil
        else {
            states[buffer.source] = nil
            throw MeetingAudioError.conversionFailed
        }
        state.totalInputFrames += Int64(buffer.frameCount)
        let expectedFrames = expectedOutputFrames(state)
        let availableFrameCount = min(
            Int64(outputBuffer.frameLength),
            max(0, expectedFrames - state.emittedFrames)
        )
        state.lastSequenceNumber = buffer.sequenceNumber
        state.emittedFrames += availableFrameCount
        states[buffer.source] = state
        let outputSamples: [Float] = if availableFrameCount > 0, let outputData = outputBuffer.floatChannelData?[0] {
            Array(UnsafeBufferPointer(start: outputData, count: Int(availableFrameCount)))
        } else {
            []
        }
        return MeetingResampledAudioBuffer(
            source: buffer.source,
            sequenceNumber: buffer.sequenceNumber,
            samples: outputSamples
        )
    }

    func finish(source: MeetingAudioSourceIdentity) throws -> MeetingResampledAudioBuffer? {
        guard var state = states.removeValue(forKey: source) else { return nil }
        var samples: [Float] = []
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            status.pointee = .endOfStream
            return nil
        }
        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: state.outputFormat, frameCapacity: 4096) else {
                throw MeetingAudioError.invalidBuffer
            }
            var conversionError: NSError?
            let status = state.converter.convert(
                to: outputBuffer,
                error: &conversionError,
                withInputFrom: inputBlock
            )
            guard status != .error, conversionError == nil else { throw MeetingAudioError.conversionFailed }
            if let outputData = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(
                    start: outputData,
                    count: Int(outputBuffer.frameLength)
                ))
            }
            if status == .endOfStream {
                break
            }
            guard outputBuffer.frameLength > 0 else { break }
        }
        let remainingFrames = max(0, expectedOutputFrames(state) - state.emittedFrames)
        let retainedFrameCount = Int(min(Int64(samples.count), remainingFrames))
        if samples.count > retainedFrameCount {
            samples.removeLast(samples.count - retainedFrameCount)
        }
        state.emittedFrames += Int64(samples.count)
        guard !samples.isEmpty else { return nil }
        return MeetingResampledAudioBuffer(
            source: source,
            sequenceNumber: state.lastSequenceNumber,
            samples: samples
        )
    }

    private func state(for buffer: MeetingOwnedAudioBuffer) throws -> ConverterState {
        let key = ConverterKey(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount)
        if let state = states[buffer.source], state.key == key {
            return state
        }
        if states[buffer.source] != nil {
            throw MeetingAudioError.invalidAudioFormat
        }
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.sampleRate,
            channels: AVAudioChannelCount(buffer.channelCount),
            interleaved: true
        ), let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(MeetingAudioFormat.sampleRateHertz),
            channels: AVAudioChannelCount(MeetingAudioFormat.channelCount),
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw MeetingAudioError.invalidAudioFormat
        }
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        converter.primeMethod = .none
        let state = ConverterState(
            key: key,
            inputFormat: inputFormat,
            outputFormat: outputFormat,
            converter: converter,
            lastSequenceNumber: buffer.sequenceNumber,
            totalInputFrames: 0,
            emittedFrames: 0
        )
        states[buffer.source] = state
        return state
    }

    private func expectedOutputFrames(_ state: ConverterState) -> Int64 {
        Int64((
            Double(state.totalInputFrames) * state.outputFormat.sampleRate / state.inputFormat.sampleRate
        ).rounded())
    }
}
