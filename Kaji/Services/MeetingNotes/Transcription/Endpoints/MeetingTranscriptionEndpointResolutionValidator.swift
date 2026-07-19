import Darwin
import Foundation

protocol MeetingTranscriptionEndpointResolving: Sendable {
    func validate(_ snapshot: MeetingTranscriptionEndpointSnapshot) async throws
}

struct MeetingTranscriptionEndpointResolutionValidator: MeetingTranscriptionEndpointResolving {
    func validate(_ snapshot: MeetingTranscriptionEndpointSnapshot) async throws {
        try snapshot.validate()
        guard snapshot.source == .custom else { return }
        let hosts = Set([snapshot.restBaseURL, snapshot.webSocketBaseURL].compactMap { text in
            text.flatMap { URL(string: $0)?.host?.lowercased() }
        })
        guard !hosts.isEmpty else { throw MeetingTranscriptionEndpointProfileError.invalidURL }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for host in hosts {
                group.addTask {
                    try Self.resolveAndValidate(host)
                }
            }
            try await group.waitForAll()
        }
    }

    private static func resolveAndValidate(_ host: String) throws {
        guard STTEndpointPolicy.isSafeCustomHost(host) else {
            throw MeetingTranscriptionEndpointProfileError.invalidURL
        }
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = host.withCString { getaddrinfo($0, nil, &hints, &result) }
        guard status == 0, let result else {
            throw MeetingTranscriptionEndpointProfileError.endpointUnavailable
        }
        defer { freeaddrinfo(result) }
        var current: UnsafeMutablePointer<addrinfo>? = result
        var validated = false
        while let info = current?.pointee {
            switch info.ai_family {
            case AF_INET:
                guard let address = info.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0.pointee }) else {
                    throw MeetingTranscriptionEndpointProfileError.invalidURL
                }
                var value = address.sin_addr
                let bytes = withUnsafeBytes(of: &value) { Array($0) }
                guard STTEndpointPolicy.isPublicIPv4(bytes) else {
                    throw MeetingTranscriptionEndpointProfileError.invalidURL
                }
                validated = true
            case AF_INET6:
                guard let address = info.ai_addr?.withMemoryRebound(to: sockaddr_in6.self, capacity: 1, { $0.pointee }) else {
                    throw MeetingTranscriptionEndpointProfileError.invalidURL
                }
                var value = address.sin6_addr
                let bytes = withUnsafeBytes(of: &value) { Array($0) }
                guard STTEndpointPolicy.isPublicIPv6(bytes) else {
                    throw MeetingTranscriptionEndpointProfileError.invalidURL
                }
                validated = true
            default:
                break
            }
            current = info.ai_next
        }
        guard validated else { throw MeetingTranscriptionEndpointProfileError.endpointUnavailable }
    }
}
