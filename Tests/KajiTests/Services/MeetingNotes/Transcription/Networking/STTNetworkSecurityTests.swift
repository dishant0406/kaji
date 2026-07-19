import Foundation
import Testing

@testable import Kaji

@Suite("STT network security")
struct STTNetworkSecurityTests {
    @Test("ephemeral sessions disable persistent request state")
    func ephemeralConfiguration() throws {
        let policy = try STTURLSessionPolicy(
            requestTimeout: 12,
            resourceTimeout: 30,
            maximumResponseBytes: 1024
        )
        let configuration = STTURLSessionConfigurationFactory.makeEphemeral(policy: policy)

        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.timeoutIntervalForRequest == 12)
        #expect(configuration.timeoutIntervalForResource == 30)
    }

    @Test("response buffers enforce declared and streamed byte limits")
    func responseLimits() throws {
        var buffer = try STTBoundedResponseBuffer(maximumBytes: 4)
        let oversized = URLResponse(
            url: try #require(URL(string: "https://api.stt.example/v1")),
            mimeType: "application/json",
            expectedContentLength: 5,
            textEncodingName: nil
        )

        #expect(throws: STTNetworkError.responseTooLarge) {
            try buffer.validate(response: oversized)
        }
        try buffer.append(Data([1, 2]))
        try buffer.append(Data([3, 4]))
        #expect(buffer.data == Data([1, 2, 3, 4]))
        #expect(throws: STTNetworkError.responseTooLarge) {
            try buffer.append(Data([5]))
        }
        #expect(buffer.data.isEmpty)
    }

    @Test("shared request policy disables intermediary and local caching")
    func noStoreHeaders() throws {
        var request = URLRequest(url: try #require(URL(string: "https://api.stt.example/v1")))

        STTRequestSecurity.apply(to: &request)

        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.value(forHTTPHeaderField: "Pragma") == "no-cache")
    }

    @Test("retry-after accepts bounded seconds and HTTP dates")
    func retryAfter() {
        let now = Date(timeIntervalSince1970: 784_111_777)

        #expect(STTRetryAfterParser.delay(from: "120", now: now, maximumDelay: 60) == 60)
        #expect(STTRetryAfterParser.delay(
            from: "Sun, 06 Nov 1994 08:49:57 GMT",
            now: now.addingTimeInterval(-30)
        ) == 50)
        #expect(STTRetryAfterParser.delay(from: "-1", now: now) == nil)
        #expect(STTRetryAfterParser.delay(from: "secret", now: now) == nil)
    }

    @Test("redaction removes userinfo query fragments and error details")
    func redaction() throws {
        let url = try #require(URL(string: "https://user:pass@api.stt.example/v1/audio?api_key=secret#token"))
        var request = URLRequest(url: url)
        request.httpMethod = "post"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

        #expect(STTNetworkRedactor.url(url) == "https://api.stt.example/v1/audio")
        #expect(STTNetworkRedactor.request(request) == "POST https://api.stt.example/v1/audio")
        #expect(STTNetworkRedactor.error(URLError(.timedOut)) == .timedOut)
        #expect(STTNetworkRedactor.error(TestSecretError()) == .connectionFailed)
    }
}

private struct TestSecretError: Error, CustomStringConvertible {
    var description: String { "secret-token-value" }
}
