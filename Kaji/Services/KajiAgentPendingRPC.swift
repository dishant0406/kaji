import Foundation

@MainActor
final class KajiAgentPendingRPC {
    private var pendingResponses: [String: (KajiAgentRPCFrame) -> Void] = [:]
    private var queuedFrames: [KajiAgentRPCFrame] = []
    private let sendFrame: (KajiAgentRPCFrame) -> Void

    init(process: KajiAgentProcess) {
        sendFrame = { process.send($0) }
    }

    init(sendFrame: @escaping (KajiAgentRPCFrame) -> Void) {
        self.sendFrame = sendFrame
    }

    var queuedFrameCount: Int {
        queuedFrames.count
    }

    var pendingResponseCount: Int {
        pendingResponses.count
    }

    func send(
        _ frame: KajiAgentRPCFrame,
        readiness: KajiAgentReadiness,
        onResponse: ((KajiAgentRPCFrame) -> Void)? = nil
    ) -> KajiAgentSendDisposition {
        var prepared = frame
        if prepared.id == nil {
            prepared.id = UUID().uuidString
        }
        if let id = prepared.id, let onResponse {
            pendingResponses[id] = onResponse
        }
        guard readiness.isReady else {
            if readiness == .checking {
                queuedFrames.append(prepared)
                return .queued
            }
            discardResponse(for: prepared)
            return .rejected(readiness.detail)
        }
        sendFrame(prepared)
        return .sent
    }

    func drainQueuedFrames() {
        let frames = queuedFrames
        queuedFrames = []
        for frame in frames {
            sendFrame(frame)
        }
    }

    func failQueuedFrames() -> [KajiAgentRPCFrame] {
        let frames = queuedFrames
        queuedFrames = []
        for frame in frames {
            discardResponse(for: frame)
        }
        return frames
    }

    func handleResponse(_ frame: KajiAgentRPCFrame) -> Bool {
        guard let id = frame.id, let handler = pendingResponses.removeValue(forKey: id) else {
            return false
        }
        handler(frame)
        return true
    }

    func discardResponse(for frame: KajiAgentRPCFrame) {
        if let id = frame.id {
            pendingResponses.removeValue(forKey: id)
        }
    }
}

enum KajiAgentSendDisposition: Equatable {
    case sent
    case queued
    case rejected(String)
}
