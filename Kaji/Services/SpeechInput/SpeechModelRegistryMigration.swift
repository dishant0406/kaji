import Foundation

enum SpeechModelRegistryMigration {
    static func migrated(
        user: SpeechModelRegistryDocument,
        bundled: SpeechModelRegistryDocument
    ) -> SpeechModelRegistryDocument {
        let bundledIDs = Set(bundled.models.map(\.id))
        let userIDs = Set(user.models.map(\.id))
        let containsBundledModel = !userIDs.isDisjoint(with: bundledIDs)
        let missingBundledModel = !bundledIDs.isSubset(of: userIDs)
        let needsBundledRefresh = user.schemaVersion < bundled.schemaVersion || (containsBundledModel && missingBundledModel)
        guard needsBundledRefresh else { return user }
        let customModels = user.models.filter { !bundledIDs.contains($0.id) }
        return SpeechModelRegistryDocument(
            schemaVersion: bundled.schemaVersion,
            models: bundled.models + customModels
        )
    }
}
