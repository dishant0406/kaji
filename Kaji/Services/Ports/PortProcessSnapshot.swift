import Foundation

struct PortProcessSnapshot: Identifiable, Equatable {
    let protocolName: String
    let address: String
    let port: Int
    let pid: Int32
    let processName: String

    var id: String {
        "\(protocolName)|\(address)|\(port)|\(pid)"
    }
}
