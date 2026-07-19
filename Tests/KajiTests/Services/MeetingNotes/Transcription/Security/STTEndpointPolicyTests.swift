import Foundation
import Testing

@testable import Kaji

@Suite("STT endpoint security")
struct STTEndpointPolicyTests {
    @Test("built-in policy accepts exact HTTPS and WSS hosts")
    func exactBuiltInHosts() throws {
        let policy = try makePolicy()

        try policy.validate(try #require(URL(string: "https://api.stt.example/v1/transcribe")), trustMode: .builtIn)
        try policy.validate(try #require(URL(string: "wss://stream.stt.example/v1/listen")), trustMode: .builtIn)
    }

    @Test("built-in policy rejects endpoint confusion attacks", arguments: [
        "http://api.stt.example/v1",
        "https://api.stt.example.evil.test/v1",
        "https://api.stt.example@evil.test/v1",
        "https://user:pass@api.stt.example/v1",
        "https://api.stt.example:8443/v1",
        "https://api.stt.example/v1#token",
        "wss://api.stt.example/v1",
    ])
    func builtInAttacks(value: String) throws {
        let policy = try makePolicy()
        let url = try #require(URL(string: value))

        #expect(throws: STTEndpointPolicyError.self) {
            try policy.validate(url, trustMode: .builtIn)
        }
    }

    @Test("custom mode rejects local and metadata literals", arguments: [
        "https://localhost/v1",
        "https://127.0.0.1/v1",
        "https://10.2.3.4/v1",
        "https://172.16.4.5/v1",
        "https://192.168.1.1/v1",
        "https://169.254.169.254/latest/meta-data",
        "https://100.100.100.200/latest/meta-data",
        "https://[::1]/v1",
        "https://[fe80::1]/v1",
        "https://[fc00::1]/v1",
        "https://[::ffff:127.0.0.1]/v1",
        "https://2130706433/v1",
    ])
    func customPrivateAddresses(value: String) throws {
        let policy = try makePolicy()
        let url = try #require(URL(string: value))

        #expect(throws: STTEndpointPolicyError.self) {
            try policy.validate(url, trustMode: .customSelfHosted)
        }
    }

    @Test("custom mode explicitly permits public hosts and literals")
    func publicCustomEndpoints() throws {
        let policy = try STTEndpointPolicy(
            httpsHosts: ["api.stt.example"],
            wssHosts: ["stream.stt.example"],
            allowsCustomSelfHosted: true
        )

        try policy.validate(try #require(URL(string: "https://speech.company.example:9443/v1")), trustMode: .customSelfHosted)
        try policy.validate(try #require(URL(string: "wss://8.8.8.8/stream")), trustMode: .customSelfHosted)
        try policy.validate(try #require(URL(string: "https://[2606:4700:4700::1111]/v1")), trustMode: .customSelfHosted)
    }

    @Test("custom endpoints are disabled by default")
    func customEndpointsDisabledInProduction() throws {
        let policy = try makePolicy()

        #expect(throws: STTEndpointPolicyError.untrustedEndpoint) {
            try policy.validate(
                try #require(URL(string: "https://speech.company.example/v1")),
                trustMode: .customSelfHosted
            )
        }
    }

    @Test("region policy rejects unknown region selectors and cross-region hosts")
    func regionPolicy() throws {
        let usPolicy = try STTEndpointPolicy(
            httpsHosts: ["us.stt.example"],
            wssHosts: ["us-stream.stt.example"]
        )
        let euPolicy = try STTEndpointPolicy(
            httpsHosts: ["eu.stt.example"],
            wssHosts: ["eu-stream.stt.example"]
        )
        let regions = try STTBuiltInRegionPolicy(regions: ["us-east-1": usPolicy, "eu-west-1": euPolicy])

        try regions.validate(
            try #require(URL(string: "https://us.stt.example/v1")),
            regionID: "us-east-1"
        )
        #expect(throws: STTEndpointPolicyError.untrustedEndpoint) {
            try regions.validate(
                try #require(URL(string: "https://eu.stt.example/v1")),
                regionID: "us-east-1"
            )
        }
        #expect(throws: STTEndpointPolicyError.untrustedEndpoint) {
            try regions.validate(
                try #require(URL(string: "https://us.stt.example/v1")),
                regionID: "us-east-1.evil"
            )
        }
    }

    @Test("cross-origin redirects strip every non-allowlisted header and body")
    func redirectCredentials() throws {
        let policy = try STTEndpointPolicy(
            httpsHosts: ["api.stt.example", "upload.stt.example"],
            wssHosts: ["stream.stt.example"]
        )
        var original = URLRequest(url: try #require(URL(string: "https://api.stt.example/start")))
        original.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        var proposed = URLRequest(url: try #require(URL(string: "https://upload.stt.example/next")))
        proposed.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        proposed.setValue("private-key", forHTTPHeaderField: "X-API-Key")
        proposed.setValue("session=secret", forHTTPHeaderField: "Cookie")
        proposed.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        proposed.setValue("application/json", forHTTPHeaderField: "Accept")
        proposed.httpBody = Data("secret-body".utf8)

        let redirected = try STTRedirectPolicy.sanitizedRequest(
            original: original,
            proposed: proposed,
            endpointPolicy: policy,
            trustMode: .builtIn
        )

        #expect(redirected.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(redirected.value(forHTTPHeaderField: "X-API-Key") == nil)
        #expect(redirected.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(redirected.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(redirected.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(redirected.httpBody == nil)
    }

    private func makePolicy() throws -> STTEndpointPolicy {
        try STTEndpointPolicy(
            httpsHosts: ["api.stt.example"],
            wssHosts: ["stream.stt.example"]
        )
    }
}
