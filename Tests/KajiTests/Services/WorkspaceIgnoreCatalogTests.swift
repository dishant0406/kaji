import Testing

@testable import Kaji

struct WorkspaceIgnoreCatalogTests {
    @Test
    func bundledCatalogContainsGeneratedDirectoryNames() {
        let catalog = WorkspaceIgnoreCatalog.bundled

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.containsDirectoryName("node_modules"))
        #expect(catalog.containsDirectoryName("DerivedData"))
        #expect(catalog.containsDirectoryName(".next"))
        #expect(catalog.containsDirectoryName(".kaji"))
    }
}
