import Foundation

enum ParentAgentThinkingLevel: String, CaseIterable, Identifiable {
    case off = "Off"
    case minimal = "Minimal"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case xhigh = "XHigh"

    var id: String { rawValue }

    var environmentValue: String {
        switch self {
        case .off: "off"
        case .minimal: "minimal"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        }
    }
}
