enum EditorCollapsedFoldPolicy {
    static func shouldResolveFoldRegions(collapsedIDs: Set<String>) -> Bool {
        !collapsedIDs.isEmpty
    }

    static func collapsedRegions(_ regions: [EditorFoldRegion], collapsedIDs: Set<String>) -> [EditorFoldRegion] {
        guard shouldResolveFoldRegions(collapsedIDs: collapsedIDs) else { return [] }
        return regions.filter { collapsedIDs.contains($0.id) }
    }
}
