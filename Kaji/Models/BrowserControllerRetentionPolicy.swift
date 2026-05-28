import Foundation

enum BrowserControllerRetentionPolicy {
    static func retainedControllerIDs(
        pageIDs: [UUID],
        selectedPageID: UUID?
    ) -> Set<UUID> {
        guard let selectedPageID, pageIDs.contains(selectedPageID) else {
            return Set(pageIDs.prefix(1))
        }
        return [selectedPageID]
    }
}
