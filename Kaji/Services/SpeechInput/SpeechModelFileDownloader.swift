import Foundation

final class SpeechModelFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let maximumBytes: Int64
    private let progress: @Sendable (Int64, Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private var session: URLSession?

    init(
        destination: URL,
        maximumBytes: Int64 = 2 * 1024 * 1024 * 1024,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.destination = destination
        self.maximumBytes = maximumBytes
        self.progress = progress
    }

    func download(request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            lock.unlock()
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesWritten <= maximumBytes else {
            setResult(.failure(SpeechModelDownloadError.downloadLimitExceeded))
            downloadTask.cancel()
            return
        }
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let response = downloadTask.response as? HTTPURLResponse, !(200 ..< 300 ~= response.statusCode) {
                throw SpeechModelDownloadError.httpStatus(
                    response.statusCode,
                    downloadTask.originalRequest?.url?.absoluteString ?? "download"
                )
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size <= maximumBytes else { throw SpeechModelDownloadError.downloadLimitExceeded }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            setResult(.success(()))
        } catch {
            setResult(.failure(error))
        }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = request
        if let url = request.url, !SpeechModelRegistrySecurity.shouldAttachToken(to: url) {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            setResult(.failure(error))
        }
        complete()
    }

    private func setResult(_ next: Result<Void, Error>) {
        lock.lock()
        if result == nil {
            result = next
        }
        lock.unlock()
    }

    private func complete() {
        lock.lock()
        let continuation = continuation
        let result = result ?? .success(())
        self.continuation = nil
        self.session?.finishTasksAndInvalidate()
        self.session = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
