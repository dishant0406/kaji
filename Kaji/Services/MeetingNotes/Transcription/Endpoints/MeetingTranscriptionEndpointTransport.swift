import Foundation

struct EndpointProfileSTTWebSocketTransportFactory: STTWebSocketTransportFactory {
    let underlying: any STTWebSocketTransportFactory
    let endpoint: MeetingTranscriptionEndpointSnapshot

    func makeTransport() -> any STTWebSocketTransporting {
        EndpointProfileSTTWebSocketTransport(
            underlying: underlying.makeTransport(),
            endpoint: endpoint
        )
    }
}

private actor EndpointProfileSTTWebSocketTransport: STTWebSocketTransporting {
    private let underlying: any STTWebSocketTransporting
    private let endpoint: MeetingTranscriptionEndpointSnapshot

    init(underlying: any STTWebSocketTransporting, endpoint: MeetingTranscriptionEndpointSnapshot) {
        self.underlying = underlying
        self.endpoint = endpoint
    }

    func events() async -> AsyncStream<STTWebSocketEvent> {
        await underlying.events()
    }

    func currentState() async -> STTWebSocketState {
        await underlying.currentState()
    }

    func connect(request: URLRequest) async throws {
        guard let requestedURL = request.url,
              let configuredText = endpoint.webSocketBaseURL,
              let configuredURL = URL(string: configuredText),
              Self.origin(requestedURL) == Self.origin(configuredURL),
              requestedURL.path.hasPrefix(configuredURL.path),
              requestedURL.user == nil,
              requestedURL.password == nil,
              requestedURL.fragment == nil
        else {
            throw STTEndpointPolicyError.untrustedEndpoint
        }
        let host = configuredURL.host?.lowercased()
        let policy = try STTEndpointPolicy(
            httpsHosts: [],
            wssHosts: Set(host.map { [$0] } ?? ["invalid.example"]),
            allowsCustomSelfHosted: endpoint.source == .custom
        )
        try policy.validate(
            requestedURL,
            trustMode: endpoint.source == .custom ? .customSelfHosted : .builtIn
        )
        var request = request
        STTRequestSecurity.apply(to: &request)
        try await underlying.connect(request: request)
    }

    func send(_ message: STTWebSocketMessage) async throws {
        try await underlying.send(message)
    }

    func ping() async throws {
        try await underlying.ping()
    }

    func close(code: Int, reason: String?) async throws {
        try await underlying.close(code: code, reason: reason)
    }

    func cancel() async {
        await underlying.cancel()
    }

    private static func origin(_ url: URL) -> String {
        "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"
    }
}
