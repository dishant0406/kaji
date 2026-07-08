import Darwin
import Foundation

protocol AIGatewayPortProcessKilling: Sendable {
    func terminate(pid: Int32) throws
    func kill(pid: Int32) throws
}

struct AIGatewayPortProcessKiller: AIGatewayPortProcessKilling {
    func terminate(pid: Int32) throws {
        try PortKiller.terminate(pid: pid)
    }

    func kill(pid: Int32) throws {
        try PortKiller.kill(pid: pid)
    }
}

struct AIGatewayPortReclaimResult: Equatable {
    let processes: [PortProcessSnapshot]

    var isEmpty: Bool { processes.isEmpty }
    var count: Int { Set(processes.map(\.pid)).count }
}

enum AIGatewayPortReclaimError: LocalizedError, Equatable {
    case stillBusy(Int, [Int32])

    var errorDescription: String? {
        switch self {
        case let .stillBusy(port, pids):
            "Port \(port) is still used by process \(pids.map(String.init).joined(separator: ", "))."
        }
    }
}

struct AIGatewayPortReclaimer {
    private let lister: AIGatewayPortProcessListing
    private let killer: AIGatewayPortProcessKilling
    private let pollIntervalNanoseconds: UInt64
    private let gracefulPolls: Int
    private let forcePolls: Int

    init(
        lister: AIGatewayPortProcessListing = AIGatewayPortProcessLister(),
        killer: AIGatewayPortProcessKilling = AIGatewayPortProcessKiller(),
        pollIntervalNanoseconds: UInt64 = 100_000_000,
        gracefulPolls: Int = 10,
        forcePolls: Int = 10
    ) {
        self.lister = lister
        self.killer = killer
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.gracefulPolls = gracefulPolls
        self.forcePolls = forcePolls
    }

    func reclaim(port: Int) async throws -> AIGatewayPortReclaimResult {
        let initial = try await lister.list(port: port)
        let pids = uniquePIDs(initial)
        guard !pids.isEmpty else { return AIGatewayPortReclaimResult(processes: []) }

        try pids.forEach(killer.terminate)
        let remainingAfterTerminate = try await waitForRelease(port: port, polls: gracefulPolls)
        let remainingPIDs = uniquePIDs(remainingAfterTerminate)
        try remainingPIDs.forEach(killer.kill)
        let remainingAfterKill = try await waitForRelease(port: port, polls: forcePolls)
        guard remainingAfterKill.isEmpty else {
            throw AIGatewayPortReclaimError.stillBusy(port, uniquePIDs(remainingAfterKill))
        }

        return AIGatewayPortReclaimResult(processes: initial)
    }

    private func waitForRelease(port: Int, polls: Int) async throws -> [PortProcessSnapshot] {
        var latest = try await lister.list(port: port)
        guard !latest.isEmpty else { return [] }
        for _ in 0 ..< polls {
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            latest = try await lister.list(port: port)
            if latest.isEmpty { return [] }
        }
        return latest
    }

    private func uniquePIDs(_ processes: [PortProcessSnapshot]) -> [Int32] {
        Array(Set(processes.map(\.pid))).sorted()
    }
}
