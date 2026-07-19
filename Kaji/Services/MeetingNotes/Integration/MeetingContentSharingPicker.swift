import Foundation
@preconcurrency import ScreenCaptureKit

enum MeetingContentPickerError: LocalizedError, Equatable {
    case cancelled
    case alreadyPresented
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Application selection was cancelled."
        case .alreadyPresented:
            "Application selection is already open."
        case .failed:
            "Application selection could not be opened."
        }
    }
}

@MainActor
protocol MeetingContentSharingPickerControlling: AnyObject {
    var defaultConfiguration: SCContentSharingPickerConfiguration { get set }
    var isActive: Bool { get set }
    func add(_ observer: any SCContentSharingPickerObserver)
    func remove(_ observer: any SCContentSharingPickerObserver)
    func present()
}

extension SCContentSharingPicker: MeetingContentSharingPickerControlling {}

@MainActor
final class MeetingContentSharingPicker: NSObject, MeetingContentPicking {
    private typealias Generation = UInt64

    private struct UncheckedContentFilter: @unchecked Sendable {
        let value: SCContentFilter
    }

    private enum Callback {
        case cancelled
        case updated(UncheckedContentFilter)
        case failed
    }

    private final class Observer: NSObject, SCContentSharingPickerObserver {
        private let deliver: @MainActor @Sendable (Callback) -> Void

        @MainActor
        init(owner: MeetingContentSharingPicker, generation: Generation) {
            deliver = { [weak owner] callback in
                owner?.receive(callback, generation: generation)
            }
        }

        nonisolated func contentSharingPicker(_: SCContentSharingPicker, didCancelFor _: SCStream?) {
            let callback = Callback.cancelled
            let deliver = deliver
            Task { @MainActor in
                deliver(callback)
            }
        }

        nonisolated func contentSharingPicker(
            _: SCContentSharingPicker,
            didUpdateWith filter: SCContentFilter,
            for _: SCStream?
        ) {
            let callback = Callback.updated(UncheckedContentFilter(value: filter))
            let deliver = deliver
            Task { @MainActor in
                deliver(callback)
            }
        }

        nonisolated func contentSharingPickerStartDidFailWithError(_: any Error) {
            let callback = Callback.failed
            let deliver = deliver
            Task { @MainActor in
                deliver(callback)
            }
        }
    }

    private struct Request {
        let generation: Generation
        let observer: Observer
        let continuation: CheckedContinuation<MeetingContentSelection, Error>
    }

    private let picker: any MeetingContentSharingPickerControlling
    private var request: Request?
    private var nextGeneration: Generation = 0
    private(set) var isActive = false

    init(picker: any MeetingContentSharingPickerControlling = SCContentSharingPicker.shared) {
        self.picker = picker
    }

    isolated deinit {
        guard let request else { return }
        picker.remove(request.observer)
        picker.isActive = false
        request.continuation.resume(throwing: MeetingContentPickerError.cancelled)
    }

    func selectApplication() async throws -> MeetingContentSelection {
        guard request == nil else { throw MeetingContentPickerError.alreadyPresented }
        guard nextGeneration < .max else { throw MeetingContentPickerError.failed }
        nextGeneration += 1
        let generation = nextGeneration

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: MeetingContentPickerError.cancelled)
                    return
                }

                let observer = Observer(owner: self, generation: generation)
                request = Request(
                    generation: generation,
                    observer: observer,
                    continuation: continuation
                )
                var configuration = SCContentSharingPickerConfiguration()
                configuration.allowedPickerModes = .singleApplication
                configuration.allowsChangingSelectedContent = false
                picker.defaultConfiguration = configuration
                picker.add(observer)
                picker.isActive = true
                isActive = true
                picker.present()
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(generation: generation)
            }
        }
    }

    func cancel() {
        guard let request else { return }
        cancel(generation: request.generation)
    }

    private func cancel(generation: Generation) {
        finish(.failure(MeetingContentPickerError.cancelled), generation: generation)
    }

    private func receive(_ callback: Callback, generation: Generation) {
        switch callback {
        case .cancelled:
            finish(.failure(MeetingContentPickerError.cancelled), generation: generation)
        case let .updated(filter):
            finish(.success(MeetingContentSelection(filter: filter.value)), generation: generation)
        case .failed:
            finish(.failure(MeetingContentPickerError.failed), generation: generation)
        }
    }

    private func finish(_ result: Result<MeetingContentSelection, Error>, generation: Generation) {
        guard let request, request.generation == generation else { return }
        self.request = nil
        picker.remove(request.observer)
        picker.isActive = false
        isActive = false
        request.continuation.resume(with: result)
    }
}
