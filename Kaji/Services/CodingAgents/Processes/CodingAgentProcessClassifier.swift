import Foundation

enum CodingAgentProcessClassifier {
    static func classify(
        processes: [CodingAgentProcessInfo],
        definitions: [CodingAgentDefinition],
        activeProcessGroupIDs: Set<Int32>
    ) -> [CodingAgentProcessMatch] {
        processes.compactMap { process in
            guard let definition = definitions.first(where: { matches(process, definition: $0) }) else { return nil }
            return CodingAgentProcessMatch(
                process: process,
                providerID: definition.id,
                providerName: definition.displayName,
                providerIconName: definition.iconName,
                providerKillPatterns: definition.processKillPatterns,
                suspicion: suspicion(for: process, activeProcessGroupIDs: activeProcessGroupIDs)
            )
        }
    }

    private static func matches(_ process: CodingAgentProcessInfo, definition: CodingAgentDefinition) -> Bool {
        let commandName = process.commandName.lowercased()
        let names = Set((definition.executableNames + definition.processMatchNames).map { $0.lowercased() })
        if names.contains(commandName) { return true }

        let commandLine = [process.commandLine, process.executablePath].compactMap(\.self).joined(separator: " ").lowercased()
        let markerMatched = definition.processCommandMarkers.contains { marker in
            commandLine.contains(marker.lowercased())
        }
        guard markerMatched else { return false }

        return !isGenericRuntime(commandName) || hasStrongMarker(commandLine, definition: definition)
    }

    private static func isGenericRuntime(_ commandName: String) -> Bool {
        ["node", "bun", "zsh", "bash", "sh", "python", "python3"].contains(commandName)
    }

    private static func hasStrongMarker(_ commandLine: String, definition: CodingAgentDefinition) -> Bool {
        definition.processCommandMarkers.contains { marker in
            let normalized = marker.lowercased()
            return commandLine.contains(normalized) && (normalized.contains("/") || normalized.contains(".") || normalized.contains("@"))
        }
    }

    private static func suspicion(
        for process: CodingAgentProcessInfo,
        activeProcessGroupIDs: Set<Int32>
    ) -> CodingAgentProcessSuspicion {
        if activeProcessGroupIDs.contains(process.processGroupID) { return .active }
        if process.parentPID == 1 { return .orphan }
        return .detached
    }
}
