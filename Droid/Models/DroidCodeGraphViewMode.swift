enum DroidCodeGraphViewMode: String, CaseIterable {
    case flow
    case map

    var label: String {
        switch self {
        case .flow:
            "Flow"
        case .map:
            "Map"
        }
    }
}
