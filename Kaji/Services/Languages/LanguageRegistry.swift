import Foundation

@MainActor
final class LanguageRegistry {
    static let shared = LanguageRegistry()

    private var definitionsByID: [String: LanguageDefinition] = [:]
    private var extensionMap: [String: String] = [:]
    private var filenameMap: [String: String] = [:]

    private init() {
        reload()
    }

    func reload() {
        let bundled = LanguagePackStore.loadBundledDefinitions()
        let user = LanguagePackStore.loadUserDefinitions()
        rebuild(with: bundled + user)
    }

    func definition(forFile filePath: String) -> LanguageDefinition? {
        let url = URL(fileURLWithPath: filePath)
        let name = url.lastPathComponent.lowercased()
        if let id = filenameMap[name] {
            return definitionsByID[id]
        }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, let id = extensionMap[ext] else { return nil }
        return definitionsByID[id]
    }

    func configuration(forFile filePath: String) -> KajiLanguageConfiguration? {
        definition(forFile: filePath)?.configuration
    }

    func allDefinitions() -> [LanguageDefinition] {
        definitionsByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func rebuild(with definitions: [LanguageDefinition]) {
        definitionsByID.removeAll(keepingCapacity: true)
        extensionMap.removeAll(keepingCapacity: true)
        filenameMap.removeAll(keepingCapacity: true)

        for definition in definitions {
            definitionsByID[definition.id] = definition
            for ext in definition.extensions {
                extensionMap[ext.lowercased()] = definition.id
            }
            for filename in definition.filenames {
                filenameMap[filename.lowercased()] = definition.id
            }
        }
    }
}
