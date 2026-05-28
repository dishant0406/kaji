import Foundation

enum BrowserPageMountPolicy {
    static func mountedPageIDs(pageIDs: [UUID], selectedPageID: UUID?) -> Set<UUID> {
        guard let selectedPageID, pageIDs.contains(selectedPageID) else {
            return Set(pageIDs.prefix(1))
        }
        return [selectedPageID]
    }
}
