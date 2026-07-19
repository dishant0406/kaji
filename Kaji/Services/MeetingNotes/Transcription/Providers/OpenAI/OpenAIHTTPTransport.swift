import Foundation

struct URLSessionOpenAIHTTPTransportFactory: OpenAIHTTPTransportFactory {
    let policy: STTURLSessionPolicy

    func makeTransport() -> any OpenAIHTTPTransporting {
        URLSessionOpenAIHTTPTransport(policy: policy)
    }
}

private final class OpenAIRedirectDenyingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor URLSessionOpenAIHTTPTransport: OpenAIHTTPTransporting {
    private let maximumResponseBytes: Int
    private let delegate: OpenAIRedirectDenyingDelegate
    private let session: URLSession
    private var cancelled = false

    init(policy: STTURLSessionPolicy) {
        maximumResponseBytes = policy.maximumResponseBytes
        delegate = OpenAIRedirectDenyingDelegate()
        session = URLSession(
            configuration: STTURLSessionConfigurationFactory.makeEphemeral(policy: policy),
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func execute(_ request: URLRequest) async throws -> OpenAIHTTPResponse {
        guard !cancelled else { throw OpenAIMeetingTranscriptionError.cancelled }
        var request = request
        STTRequestSecurity.apply(to: &request)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  let finalURL = httpResponse.url
            else {
                throw OpenAIMeetingTranscriptionError.invalidResponse
            }
            guard httpResponse.expectedContentLength < 0 ||
                httpResponse.expectedContentLength <= Int64(maximumResponseBytes)
            else {
                throw OpenAIMeetingTranscriptionError.responseTooLarge
            }
            var body = Data()
            body.reserveCapacity(min(maximumResponseBytes, max(0, Int(httpResponse.expectedContentLength))))
            for try await byte in bytes {
                guard body.count < maximumResponseBytes else {
                    throw OpenAIMeetingTranscriptionError.responseTooLarge
                }
                body.append(byte)
            }
            guard !cancelled else { throw OpenAIMeetingTranscriptionError.cancelled }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                guard let key = entry.key as? String, let value = entry.value as? String else { return }
                result[key] = value
            }
            return try OpenAIHTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: body,
                finalURL: finalURL
            )
        } catch is CancellationError {
            throw OpenAIMeetingTranscriptionError.cancelled
        } catch let error as OpenAIMeetingTranscriptionError {
            throw error
        } catch {
            throw STTNetworkRedactor.error(error)
        }
    }

    func cancel() {
        cancelled = true
        session.invalidateAndCancel()
    }

    deinit {
        session.invalidateAndCancel()
    }
}
