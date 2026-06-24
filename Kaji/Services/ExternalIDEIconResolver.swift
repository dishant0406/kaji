import Foundation

struct ExternalIDEIconResolver {
    let catalog: ExternalIDECatalog

    init(catalog: ExternalIDECatalog = ExternalIDECatalog()) {
        self.catalog = catalog
    }

    func iconPath(for ide: ExternalIDE) -> String? {
        catalog.resolvedApplicationURL(for: ide)?.path
    }

    func iconPaths(for ides: [ExternalIDE]) -> [String: String] {
        ides.reduce(into: [:]) { paths, ide in
            guard let path = iconPath(for: ide) else { return }
            paths[ide.id] = path
        }
    }
}
