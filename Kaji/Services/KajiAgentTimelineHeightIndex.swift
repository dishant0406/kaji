import CoreGraphics
import Observation

struct KajiAgentHeightMeasurementResult: Equatable {
    let correction: CGFloat
    let changedCount: Int
}

@MainActor
@Observable
final class KajiAgentTimelineHeightIndex {
    private(set) var version = 0
    private var rows: [KajiAgentTimelineRow] = []
    private var heights: [CGFloat] = []
    private var prefixSums: [CGFloat] = [0]
    private var measuredHeights: [KajiAgentTimelineRowID: CGFloat] = [:]
    private var rowIDs: [KajiAgentTimelineRowID] = []

    func sync(rows nextRows: [KajiAgentTimelineRow]) {
        guard rowIDs != nextRows.map(\.id) || rows != nextRows else { return }
        let oldRowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for row in nextRows where oldRowsByID[row.id] != nil && oldRowsByID[row.id] != row {
            measuredHeights.removeValue(forKey: row.id)
        }
        rows = nextRows
        rowIDs = nextRows.map(\.id)
        let liveIDs = Set(rowIDs)
        measuredHeights = measuredHeights.filter { liveIDs.contains($0.key) }
        heights = nextRows.map { measuredHeights[$0.id] ?? KajiAgentTimelineHeightEstimator.estimate($0) }
        rebuildPrefixSums()
        version &+= 1
    }

    func invalidate(_ id: KajiAgentTimelineRowID?) {
        guard let id else { return }
        measuredHeights.removeValue(forKey: id)
        version &+= 1
    }

    func height(for row: KajiAgentTimelineRow) -> CGFloat {
        measuredHeights[row.id] ?? KajiAgentTimelineHeightEstimator.estimate(row)
    }

    func layout(scrollOffset: CGFloat, viewportHeight: CGFloat, overscanScreens: CGFloat = 2) -> KajiAgentVisibleLayout {
        guard !heights.isEmpty else {
            return KajiAgentVisibleLayout(range: 0 ..< 0, topSpacerHeight: 0, bottomSpacerHeight: 0, totalHeight: 0)
        }
        let totalHeight = prefixSums.last ?? 0
        let overscan = max(viewportHeight, 1) * max(overscanScreens, 0)
        let startY = max(0, scrollOffset - overscan)
        let endY = min(totalHeight, scrollOffset + viewportHeight + overscan)
        let lower = index(at: startY)
        let upper = min(heights.count, index(after: endY))
        let top = prefixSums[lower]
        let visible = prefixSums[upper] - top
        return KajiAgentVisibleLayout(
            range: lower ..< upper,
            topSpacerHeight: top,
            bottomSpacerHeight: max(0, totalHeight - top - visible),
            totalHeight: totalHeight
        )
    }

    func applyMeasurements(
        _ values: [KajiAgentTimelineRowHeightValue],
        rowStore: KajiAgentTimelineRowStore,
        scrollOffset: CGFloat
    ) -> KajiAgentHeightMeasurementResult {
        var correction: CGFloat = 0
        var changedCount = 0
        for value in values {
            guard let index = rowStore.index(for: value.id), heights.indices.contains(index) else { continue }
            let rounded = ceil(value.height)
            guard rounded.isFinite, rounded >= 0, abs(heights[index] - rounded) > 0.5 else { continue }
            let delta = rounded - heights[index]
            measuredHeights[value.id] = rounded
            heights[index] = rounded
            if prefixSums[index] < scrollOffset {
                correction += delta
            }
            changedCount += 1
        }
        guard changedCount > 0 else { return KajiAgentHeightMeasurementResult(correction: 0, changedCount: 0) }
        rebuildPrefixSums()
        version &+= 1
        return KajiAgentHeightMeasurementResult(correction: correction, changedCount: changedCount)
    }

    private func rebuildPrefixSums() {
        prefixSums = [0]
        prefixSums.reserveCapacity(heights.count + 1)
        for height in heights {
            prefixSums.append((prefixSums.last ?? 0) + height)
        }
    }

    private func index(at offset: CGFloat) -> Int {
        var low = 0
        var high = heights.count
        while low < high {
            let mid = (low + high) / 2
            if prefixSums[mid + 1] < offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return min(low, max(heights.count - 1, 0))
    }

    private func index(after offset: CGFloat) -> Int {
        var low = 0
        var high = heights.count
        while low < high {
            let mid = (low + high) / 2
            if prefixSums[mid] <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, min(low, heights.count - 1))
    }
}
