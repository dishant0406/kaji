import Testing

@testable import Kaji

@MainActor
struct KajiAgentPendingRPCTests {
    @Test
    func queuesFramesWhileRuntimeIsChecking() {
        var sent: [KajiAgentRPCFrame] = []
        let pending = KajiAgentPendingRPC { sent.append($0) }

        let result = pending.send(KajiAgentRPCFrame(type: "get_state"), readiness: .checking)

        #expect(result == .queued)
        #expect(sent.isEmpty)
        #expect(pending.queuedFrameCount == 1)
    }

    @Test
    func drainsQueuedFramesInOrder() {
        var sent: [KajiAgentRPCFrame] = []
        let pending = KajiAgentPendingRPC { sent.append($0) }

        _ = pending.send(KajiAgentRPCFrame(type: "first"), readiness: .checking)
        _ = pending.send(KajiAgentRPCFrame(type: "second"), readiness: .checking)
        pending.drainQueuedFrames()

        #expect(sent.map(\.type) == ["first", "second"])
        #expect(pending.queuedFrameCount == 0)
    }

    @Test
    func removesResponseHandlerWhenQueuedFrameFails() {
        var handled = false
        let pending = KajiAgentPendingRPC { _ in }

        _ = pending.send(
            KajiAgentRPCFrame(id: "queued", type: "prompt"),
            readiness: .checking,
            onResponse: { _ in handled = true }
        )
        let failed = pending.failQueuedFrames()
        let consumed = pending.handleResponse(KajiAgentRPCFrame(id: "queued", type: "response"))

        #expect(failed.map(\.id) == ["queued"])
        #expect(!consumed)
        #expect(!handled)
        #expect(pending.pendingResponseCount == 0)
    }

    @Test
    func handlesMatchingResponseOnce() {
        var handledCommands: [String] = []
        let pending = KajiAgentPendingRPC { _ in }

        _ = pending.send(
            KajiAgentRPCFrame(id: "request", type: "get_state"),
            readiness: .ready,
            onResponse: { handledCommands.append($0.command ?? "") }
        )

        let first = pending.handleResponse(KajiAgentRPCFrame(id: "request", type: "response", command: "get_state"))
        let second = pending.handleResponse(KajiAgentRPCFrame(id: "request", type: "response", command: "get_state"))

        #expect(first)
        #expect(!second)
        #expect(handledCommands == ["get_state"])
    }
}
