import Foundation

struct NativeRenderMetricsSnapshot: Codable, Equatable {
    var frameUpdates = 0
    var fullFrameUpdates = 0
    var partialFrameUpdates = 0
    var presentedFrames = 0
    var skippedPresents = 0
    var fullRenderPlanRebuilds = 0
    var partialRenderPlanRebuilds = 0
    var patchedCells = 0
    var rebuiltRows = 0

    var encodedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

final class NativeRenderMetricsRecorder {
    private(set) var snapshot = NativeRenderMetricsSnapshot()

    func recordFrameUpdate(_ update: TerminalFrameUpdate, applyResult: TerminalFrameStoreApplyResult) {
        snapshot.frameUpdates += 1
        snapshot.patchedCells += applyResult.patchedCellCount
        switch update.damage {
        case .full:
            snapshot.fullFrameUpdates += 1
        case .partial:
            snapshot.partialFrameUpdates += 1
        case .none:
            break
        }
    }

    func recordPresentedFrame(planStats: TerminalRenderPlanStats) {
        snapshot.presentedFrames += 1
        snapshot.rebuiltRows += planStats.rebuiltRowCount
        if planStats.wasFullRebuild {
            snapshot.fullRenderPlanRebuilds += 1
        } else {
            snapshot.partialRenderPlanRebuilds += 1
        }
    }

    func recordSkippedPresent() {
        snapshot.skippedPresents += 1
    }

    func reset() {
        snapshot = NativeRenderMetricsSnapshot()
    }
}
