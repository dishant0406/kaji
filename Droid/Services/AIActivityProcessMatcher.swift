import Foundation

enum AIActivityProcessMatcher {
    static func matches(providerID: String, processNames: [String]) -> Bool {
        switch providerID {
        case "codex":
            contains(processNames: processNames, needle: "codex")
        case "claude":
            contains(processNames: processNames, needle: "claude")
        case "opencode":
            contains(processNames: processNames, needle: "opencode")
        default:
            true
        }
    }

    private static func contains(processNames: [String], needle: String) -> Bool {
        processNames.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
