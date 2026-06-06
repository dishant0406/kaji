struct KajiAgentRuntimeErrorGate {
    private var visibleDecodeErrors = 0

    mutating func shouldShow(_ error: String) -> Bool {
        guard error.hasPrefix("Failed to decode runtime event") else { return true }
        visibleDecodeErrors += 1
        return visibleDecodeErrors <= 3
    }

    mutating func reset() {
        visibleDecodeErrors = 0
    }
}
