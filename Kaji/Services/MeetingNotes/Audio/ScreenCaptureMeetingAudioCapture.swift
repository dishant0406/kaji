@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import os
@preconcurrency import ScreenCaptureKit

@MainActor
protocol MeetingAudioCaptureSession: AnyObject {
    var isCapturing: Bool { get }
    func start() async throws
    func stop() async throws
}

@MainActor
final class ScreenCaptureMeetingAudioCapture: NSObject, MeetingAudioCaptureSession {
    let configuration: SCStreamConfiguration

    private let stream: SCStream
    private let systemAudioOutput: ScreenCaptureMeetingAudioOutput?
    private let microphoneOutput: ScreenCaptureMeetingAudioOutput?
    private let streamDelegate: ScreenCaptureMeetingAudioStreamDelegate
    private(set) var isCapturing = false

    init(
        filter: SCContentFilter,
        microphoneCaptureDeviceID: String?,
        systemAudioSource: MeetingAudioSourceIdentity?,
        microphoneSource: MeetingAudioSourceIdentity?,
        ingress: MeetingAudioQueueIngress
    ) throws {
        guard systemAudioSource != nil || microphoneSource != nil,
              systemAudioSource?.kind == .systemAudio || systemAudioSource == nil,
              microphoneSource?.kind == .microphone || microphoneSource == nil
        else {
            throw MeetingAudioError.invalidAudioFormat
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = systemAudioSource != nil
        configuration.captureMicrophone = microphoneSource != nil
        configuration.microphoneCaptureDeviceID = microphoneCaptureDeviceID
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        self.configuration = configuration
        systemAudioOutput = systemAudioSource.map { ScreenCaptureMeetingAudioOutput(source: $0, ingress: ingress) }
        microphoneOutput = microphoneSource.map { ScreenCaptureMeetingAudioOutput(source: $0, ingress: ingress) }
        streamDelegate = ScreenCaptureMeetingAudioStreamDelegate(ingress: ingress)
        stream = SCStream(filter: filter, configuration: configuration, delegate: streamDelegate)
        super.init()
    }

    func start() async throws {
        guard !isCapturing else { throw MeetingAudioError.captureAlreadyRunning }
        if microphoneOutput != nil, await !hasMicrophoneAccess() {
            throw MeetingAudioError.microphonePermissionDenied
        }
        do {
            if let systemAudioOutput {
                try stream.addStreamOutput(systemAudioOutput, type: .audio, sampleHandlerQueue: systemAudioOutput.queue)
            }
            if let microphoneOutput {
                try stream.addStreamOutput(microphoneOutput, type: .microphone, sampleHandlerQueue: microphoneOutput.queue)
            }
            try await stream.startCapture()
            isCapturing = true
        } catch {
            if let systemAudioOutput { try? stream.removeStreamOutput(systemAudioOutput, type: .audio) }
            if let microphoneOutput { try? stream.removeStreamOutput(microphoneOutput, type: .microphone) }
            throw MeetingAudioError.streamSetupFailed(String(describing: error))
        }
    }

    func stop() async throws {
        guard isCapturing else { throw MeetingAudioError.captureNotRunning }
        var stopError: Error?
        do {
            try await stream.stopCapture()
        } catch {
            stopError = error
        }
        isCapturing = false
        if let systemAudioOutput {
            do {
                try stream.removeStreamOutput(systemAudioOutput, type: .audio)
            } catch {
                stopError = stopError ?? error
            }
        }
        if let microphoneOutput {
            do {
                try stream.removeStreamOutput(microphoneOutput, type: .microphone)
            } catch {
                stopError = stopError ?? error
            }
        }
        guard let stopError else { return }
        throw MeetingAudioError.streamSetupFailed(String(describing: stopError))
    }

    private func hasMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied,
             .restricted:
            false
        @unknown default:
            false
        }
    }
}

private final class ScreenCaptureMeetingAudioOutput: NSObject, SCStreamOutput {
    let queue: DispatchQueue

    private let source: MeetingAudioSourceIdentity
    private let ingress: MeetingAudioQueueIngress
    private let sequence = OSAllocatedUnfairLock(initialState: Int64(0))
    private let copier = MeetingSampleBufferAudioCopier()

    init(source: MeetingAudioSourceIdentity, ingress: MeetingAudioQueueIngress) {
        self.source = source
        self.ingress = ingress
        queue = DispatchQueue(label: "com.kaji.meeting-audio.\(source.kind.rawValue)", qos: .userInitiated)
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of _: SCStreamOutputType) {
        let sequenceNumber = sequence.withLock { value -> Int64 in
            defer { value += 1 }
            return value
        }
        let capturedAtMilliseconds = max(
            source.startedAtMilliseconds,
            Int64(Date().timeIntervalSince1970 * 1000)
        )
        do {
            let buffer = try copier.copy(
                sampleBuffer,
                source: source,
                sequenceNumber: sequenceNumber,
                capturedAtMilliseconds: capturedAtMilliseconds
            )
            switch ingress.submit(buffer).disposition {
            case .accepted,
                 .dropped:
                break
            case .closed:
                return
            }
        } catch {
            let frameCount = max(1, CMSampleBufferGetNumSamples(sampleBuffer))
            let sampleRate = CMSampleBufferGetFormatDescription(sampleBuffer)
                .flatMap(CMAudioFormatDescriptionGetStreamBasicDescription)?
                .pointee.mSampleRate ?? 48000
            ingress.submit(MeetingAudioGap(
                source: source,
                sequenceNumber: sequenceNumber,
                capturedAtMilliseconds: capturedAtMilliseconds,
                frameCount: frameCount,
                sampleRate: sampleRate,
                reason: .conversionFailure
            ))
            ingress.submit(MeetingAudioCaptureFailure(
                domain: "Kaji.MeetingAudio.SampleBuffer",
                code: 1,
                message: String(describing: error),
                source: source,
                sequenceNumber: sequenceNumber,
                capturedAtMilliseconds: capturedAtMilliseconds,
                frameCount: frameCount
            ))
        }
    }
}

private final class ScreenCaptureMeetingAudioStreamDelegate: NSObject, SCStreamDelegate {
    private let ingress: MeetingAudioQueueIngress

    init(ingress: MeetingAudioQueueIngress) {
        self.ingress = ingress
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        let nsError = error as NSError
        ingress.submit(MeetingAudioCaptureFailure(
            domain: nsError.domain,
            code: nsError.code,
            message: nsError.localizedDescription
        ))
    }
}
