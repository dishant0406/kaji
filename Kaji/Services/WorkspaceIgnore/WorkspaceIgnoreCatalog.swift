import Foundation

struct WorkspaceIgnoreCatalog: Decodable, Equatable {
    let schemaVersion: Int
    let sourceTemplateCounts: [String: Int]
    let directoryNames: [String]

    static let bundled = loadBundled()

    var directoryNameSet: Set<String> {
        Set(directoryNames)
    }

    func containsDirectoryName(_ name: String) -> Bool {
        directoryNameSet.contains(name)
    }

    func containsIgnoredComponent(in path: String) -> Bool {
        let names = directoryNameSet
        return path.split(separator: "/").contains { names.contains(String($0)) }
    }

    private static func loadBundled() -> WorkspaceIgnoreCatalog {
        let fallback = WorkspaceIgnoreCatalog(
            schemaVersion: 1,
            sourceTemplateCounts: [:],
            directoryNames: [".git", ".kaji"]
        )
        let urls = [
            Bundle.appResources.url(
                forResource: "generated-ignore-catalog",
                withExtension: "json",
                subdirectory: "WorkspaceIgnore"
            ),
            Bundle.main.url(
                forResource: "generated-ignore-catalog",
                withExtension: "json",
                subdirectory: "WorkspaceIgnore"
            ),
        ]
        for case let url? in urls {
            guard let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(WorkspaceIgnoreCatalog.self, from: data),
                  catalog.schemaVersion == 1,
                  !catalog.directoryNames.isEmpty
            else { continue }
            return catalog
        }
        return fallback
    }
}
