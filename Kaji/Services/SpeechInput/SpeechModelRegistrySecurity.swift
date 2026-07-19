import Foundation

enum SpeechModelRegistrySecurity {
    static let trustedHost = "huggingface.co"

    static func isTrustedBaseURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == trustedHost,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return false
        }
        return true
    }

    static func shouldAttachToken(to url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" &&
            components.host?.lowercased() == trustedHost &&
            components.port == nil &&
            components.user == nil &&
            components.password == nil
    }

    static func isSafeRepository(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { isSafeComponent(String($0)) }
    }

    static func isSafeRevision(_ value: String) -> Bool {
        isSafeComponent(value)
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200, value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-"
        }
    }
}
