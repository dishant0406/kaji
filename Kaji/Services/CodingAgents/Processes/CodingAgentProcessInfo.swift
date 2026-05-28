import Foundation

struct CodingAgentProcessInfo: Identifiable, Equatable {
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let state: String
    let tty: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let threadCount: Int
    let commandName: String
    let executablePath: String?
    let commandLine: String

    var id: Int32 { pid }
}

enum CodingAgentProcessSuspicion: String, Equatable {
    case active
    case orphan
    case detached
}

struct CodingAgentProcessMatch: Identifiable, Equatable {
    let process: CodingAgentProcessInfo
    let providerID: String
    let providerName: String
    let providerIconName: String
    let providerKillPatterns: [String]
    let suspicion: CodingAgentProcessSuspicion

    var id: String { "\(providerID)|\(process.pid)" }
}

struct CodingAgentProcessProviderGroup: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let iconName: String
    let killPatterns: [String]
    let processes: [CodingAgentProcessMatch]

    var id: String { providerID }
    var orphanCount: Int { processes.count(where: { $0.suspicion == .orphan }) }
    var cpuPercent: Double { processes.reduce(0) { $0 + $1.process.cpuPercent } }
    var memoryBytes: UInt64 { processes.reduce(0) { $0 + $1.process.memoryBytes } }
}
