import Foundation
import Testing

@testable import Kaji

@Suite("AI Gateway port reclaimer")
struct AIGatewayPortReclaimerTests {
    @Test("terminates every process listening on the gateway port")
    func terminatesListeningProcesses() async throws {
        let first = snapshot(pid: 120, processName: "node")
        let second = snapshot(pid: 121, processName: "python")
        let lister = FakeGatewayPortLister(responses: [[first, first, second], []])
        let killer = FakeGatewayPortKiller()
        let reclaimer = AIGatewayPortReclaimer(lister: lister, killer: killer, pollIntervalNanoseconds: 1, gracefulPolls: 1, forcePolls: 1)

        let result = try await reclaimer.reclaim(port: 5254)

        #expect(result.count == 2)
        #expect(killer.terminated == [120, 121])
        #expect(killer.killed.isEmpty)
    }

    @Test("force kills processes that survive graceful termination")
    func forceKillsRemainingProcesses() async throws {
        let process = snapshot(pid: 220, processName: "gateway")
        let lister = FakeGatewayPortLister(responses: [[process], [process], [process], []])
        let killer = FakeGatewayPortKiller()
        let reclaimer = AIGatewayPortReclaimer(lister: lister, killer: killer, pollIntervalNanoseconds: 1, gracefulPolls: 1, forcePolls: 1)

        _ = try await reclaimer.reclaim(port: 5254)

        #expect(killer.terminated == [220])
        #expect(killer.killed == [220])
    }

    @Test("throws when the port remains busy")
    func throwsWhenPortRemainsBusy() async throws {
        let process = snapshot(pid: 320, processName: "gateway")
        let lister = FakeGatewayPortLister(responses: [[process], [process], [process], [process], [process]])
        let killer = FakeGatewayPortKiller()
        let reclaimer = AIGatewayPortReclaimer(lister: lister, killer: killer, pollIntervalNanoseconds: 1, gracefulPolls: 1, forcePolls: 1)

        do {
            _ = try await reclaimer.reclaim(port: 5254)
            Issue.record("Expected reclaim to fail")
        } catch let error as AIGatewayPortReclaimError {
            #expect(error == .stillBusy(5254, [320]))
        }
    }

    private func snapshot(pid: Int32, processName: String) -> PortProcessSnapshot {
        PortProcessSnapshot(protocolName: "TCP", address: "127.0.0.1", port: 5254, pid: pid, processName: processName)
    }
}

private actor FakeGatewayPortLister: AIGatewayPortProcessListing {
    private var responses: [[PortProcessSnapshot]]
    private(set) var requestedPorts: [Int] = []

    init(responses: [[PortProcessSnapshot]]) {
        self.responses = responses
    }

    func list(port: Int) async throws -> [PortProcessSnapshot] {
        requestedPorts.append(port)
        guard !responses.isEmpty else { return [] }
        return responses.removeFirst()
    }
}

private final class FakeGatewayPortKiller: AIGatewayPortProcessKilling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var terminated: [Int32] = []
    private(set) var killed: [Int32] = []

    func terminate(pid: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        terminated.append(pid)
    }

    func kill(pid: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        killed.append(pid)
    }
}
