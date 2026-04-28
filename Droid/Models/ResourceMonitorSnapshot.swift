import Foundation

struct ResourceMonitorTerminalDescriptor: Identifiable, Equatable {
    let paneID: UUID
    let tabID: UUID
    let areaID: UUID
    let projectID: UUID
    let projectName: String
    let title: String

    var id: UUID { paneID }
}

struct ResourceMonitorTerminalReading: Identifiable, Equatable {
    let descriptor: ResourceMonitorTerminalDescriptor
    let processGroupID: Int32?
    let pid: Int32?
    let processName: String?
    let ttyName: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let threadCount: Int?

    var id: UUID { descriptor.id }
}

struct ResourceMonitorTerminalSnapshot: Identifiable, Equatable {
    let paneID: UUID
    let tabID: UUID
    let areaID: UUID
    let projectID: UUID
    let title: String
    let processGroupID: Int32?
    let pid: Int32?
    let processName: String?
    let ttyName: String?
    let cpuPercent: Double?
    let memoryBytes: UInt64?
    let threadCount: Int?

    var id: UUID { paneID }
}

struct ResourceMonitorProjectSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let terminals: [ResourceMonitorTerminalSnapshot]
}
