import Foundation

struct PendingLanguagePackInstall: Identifiable, Equatable {
    let id = UUID()
    let filePath: String
    let entry: LanguagePackCatalogEntry
}
