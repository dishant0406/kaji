import Darwin
import Foundation

enum STTEndpointPolicyError: Error, Equatable {
    case invalidEndpoint
    case untrustedEndpoint
    case invalidRedirect
}

enum STTEndpointTrustMode {
    case builtIn
    case customSelfHosted
}

struct STTEndpointPolicy {
    private let httpsHosts: Set<String>
    private let wssHosts: Set<String>
    private let allowsCustomSelfHosted: Bool

    init(
        httpsHosts: Set<String>,
        wssHosts: Set<String>,
        allowsCustomSelfHosted: Bool = false
    ) throws {
        let normalizedHTTPS = try Self.normalizedAllowedHosts(httpsHosts)
        let normalizedWSS = try Self.normalizedAllowedHosts(wssHosts)
        guard !normalizedHTTPS.isEmpty || !normalizedWSS.isEmpty else {
            throw STTEndpointPolicyError.invalidEndpoint
        }
        self.httpsHosts = normalizedHTTPS
        self.wssHosts = normalizedWSS
        self.allowsCustomSelfHosted = allowsCustomSelfHosted
    }

    func validate(_ url: URL, trustMode: STTEndpointTrustMode) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let rawHost = components.host?.lowercased(),
              !rawHost.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.percentEncodedHost?.contains("%") == false,
              scheme == "https" || scheme == "wss"
        else {
            throw STTEndpointPolicyError.invalidEndpoint
        }
        let host = rawHost.hasPrefix("[") && rawHost.hasSuffix("]") ?
            String(rawHost.dropFirst().dropLast()) : rawHost
        switch trustMode {
        case .builtIn:
            guard components.port == nil || components.port == 443 else {
                throw STTEndpointPolicyError.invalidEndpoint
            }
            let allowedHosts = scheme == "https" ? httpsHosts : wssHosts
            guard allowedHosts.contains(host) else {
                throw STTEndpointPolicyError.untrustedEndpoint
            }
        case .customSelfHosted:
            guard allowsCustomSelfHosted else {
                throw STTEndpointPolicyError.untrustedEndpoint
            }
            if let port = components.port, !(1 ... 65535).contains(port) {
                throw STTEndpointPolicyError.invalidEndpoint
            }
            guard Self.isSafeCustomHost(host) else {
                throw STTEndpointPolicyError.untrustedEndpoint
            }
        }
    }

    private static func normalizedAllowedHosts(_ hosts: Set<String>) throws -> Set<String> {
        var normalized = Set<String>()
        for host in hosts {
            let value = host.lowercased()
            guard isValidDNSName(value), value == host else {
                throw STTEndpointPolicyError.invalidEndpoint
            }
            normalized.insert(value)
        }
        return normalized
    }

    static func isSafeCustomHost(_ host: String) -> Bool {
        guard !host.contains("%"),
              host != "localhost",
              host != "metadata",
              host != "metadata.google.internal",
              host != "instance-data"
        else {
            return false
        }
        if let ipv4 = parseIPv4(host) {
            return isPublicIPv4(ipv4)
        }
        if let ipv6 = parseIPv6(host) {
            return isPublicIPv6(ipv6)
        }
        guard !host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) else {
            return false
        }
        return isValidDNSName(host)
    }

    private static func isValidDNSName(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasSuffix(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-"
            else {
                return false
            }
            return label.utf8.allSatisfy { byte in
                byte >= 0x61 && byte <= 0x7A ||
                    byte >= 0x30 && byte <= 0x39 || byte == 0x2D
            }
        }
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        var address = in_addr()
        let parsed = host.withCString { inet_pton(AF_INET, $0, &address) }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let parsed = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]
        if first == 0 || first == 10 || first == 127 || first >= 224 {
            return false
        }
        if first == 100, second >= 64, second <= 127 {
            return false
        }
        if first == 169, second == 254 {
            return false
        }
        if first == 172, second >= 16, second <= 31 {
            return false
        }
        if first == 192, second == 168 {
            return false
        }
        if first == 192, second == 0, bytes[2] == 0 {
            return false
        }
        if first == 198, second == 18 || second == 19 {
            return false
        }
        if first == 100, second == 100, bytes[2] == 100, bytes[3] == 200 {
            return false
        }
        return true
    }

    static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) {
            return false
        }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 {
            return false
        }
        if bytes[0] == 0xFC || bytes[0] == 0xFD {
            return false
        }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
            return false
        }
        if bytes[0] == 0xFF {
            return false
        }
        let mappedPrefix = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        if mappedPrefix {
            return isPublicIPv4(Array(bytes.suffix(4)))
        }
        return true
    }
}

struct STTBuiltInRegionPolicy {
    private let regions: [String: STTEndpointPolicy]

    init(regions: [String: STTEndpointPolicy]) throws {
        guard !regions.isEmpty, regions.keys.allSatisfy(Self.isValidRegionID) else {
            throw STTEndpointPolicyError.invalidEndpoint
        }
        self.regions = regions
    }

    func validate(_ url: URL, regionID: String) throws {
        guard let policy = regions[regionID] else {
            throw STTEndpointPolicyError.untrustedEndpoint
        }
        try policy.validate(url, trustMode: .builtIn)
    }

    private static func isValidRegionID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 32 else { return false }
        return value.utf8.allSatisfy { byte in
            byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 || byte == 0x2D
        }
    }
}

enum STTRedirectPolicy {
    static func sanitizedRequest(
        original: URLRequest,
        proposed: URLRequest,
        endpointPolicy: STTEndpointPolicy,
        trustMode: STTEndpointTrustMode
    ) throws -> URLRequest {
        guard let originalURL = original.url, let proposedURL = proposed.url else {
            throw STTEndpointPolicyError.invalidRedirect
        }
        try endpointPolicy.validate(proposedURL, trustMode: trustMode)
        var sanitized = proposed
        guard origin(of: originalURL) != origin(of: proposedURL) else { return sanitized }
        let allowedHeaders = Set(["accept", "accept-language", "user-agent"])
        let headers = sanitized.allHTTPHeaderFields.map { Array($0.keys) } ?? []
        for header in headers where !allowedHeaders.contains(header.lowercased()) {
            sanitized.setValue(nil, forHTTPHeaderField: header)
        }
        sanitized.httpBody = nil
        sanitized.httpBodyStream = nil
        return sanitized
    }

    private static func origin(of url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme?.lowercased() ?? ""
        let host = components?.host?.lowercased() ?? ""
        let port = components?.port ?? 443
        return "\(scheme)://\(host):\(port)"
    }
}
