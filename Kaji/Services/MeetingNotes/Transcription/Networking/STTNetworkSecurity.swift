import Foundation

enum STTNetworkError: Error, Equatable {
    case invalidConfiguration
    case invalidResponse
    case responseTooLarge
    case timedOut
    case cancelled
    case connectionFailed
    case protocolViolation
}

struct STTURLSessionPolicy: Equatable {
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let maximumResponseBytes: Int

    init(
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 120,
        maximumResponseBytes: Int = 16 * 1024 * 1024
    ) throws {
        guard requestTimeout.isFinite,
              resourceTimeout.isFinite,
              requestTimeout >= 1,
              requestTimeout <= 300,
              resourceTimeout >= requestTimeout,
              resourceTimeout <= 900,
              maximumResponseBytes >= 1,
              maximumResponseBytes <= 64 * 1024 * 1024
        else {
            throw STTNetworkError.invalidConfiguration
        }
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes
    }
}

enum STTURLSessionConfigurationFactory {
    static func makeEphemeral(policy: STTURLSessionPolicy) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = policy.requestTimeout
        configuration.timeoutIntervalForResource = policy.resourceTimeout
        configuration.waitsForConnectivity = false
        return configuration
    }
}

enum STTRequestSecurity {
    static func apply(to request: inout URLRequest) {
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
    }
}

struct STTBoundedResponseBuffer {
    let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int) throws {
        guard maximumBytes >= 1, maximumBytes <= 64 * 1024 * 1024 else {
            throw STTNetworkError.invalidConfiguration
        }
        self.maximumBytes = maximumBytes
    }

    mutating func append(_ chunk: Data) throws {
        guard chunk.count <= maximumBytes - data.count else {
            data.removeAll(keepingCapacity: false)
            throw STTNetworkError.responseTooLarge
        }
        data.append(chunk)
    }

    func validate(response: URLResponse) throws {
        let expected = response.expectedContentLength
        guard expected < 0 || expected <= Int64(maximumBytes) else {
            throw STTNetworkError.responseTooLarge
        }
    }
}

enum STTRetryAfterParser {
    static func delay(
        from value: String?,
        now: Date = Date(),
        maximumDelay: TimeInterval = 3600
    ) -> TimeInterval? {
        guard let value,
              maximumDelay.isFinite,
              maximumDelay >= 0
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = UInt64(trimmed), seconds <= UInt64(Int.max) {
            return min(TimeInterval(seconds), maximumDelay)
        }
        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss z",
            "EEEE',' dd-MMM-yy HH':'mm':'ss z",
            "EEE MMM d HH':'mm':'ss yyyy",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return min(max(0, date.timeIntervalSince(now)), maximumDelay)
            }
        }
        return nil
    }
}

enum STTNetworkRedactor {
    static func url(_ url: URL?) -> String {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else {
            return "<redacted-url>"
        }
        var value = "\(scheme)://\(host)"
        if let port = components.port { value += ":\(port)" }
        let path = components.percentEncodedPath
        if !path.isEmpty { value += path }
        return value
    }

    static func request(_ request: URLRequest) -> String {
        let method = request.httpMethod?.uppercased() ?? "REQUEST"
        return "\(method) \(url(request.url))"
    }

    static func error(_ error: Error) -> STTNetworkError {
        if error is CancellationError { return .cancelled }
        if let networkError = error as? STTNetworkError { return networkError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            default:
                return .connectionFailed
            }
        }
        return .connectionFailed
    }
}
