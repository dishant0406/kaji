import Foundation

struct KajiBrowserBrokerState: Equatable {
    let port: UInt16
    let token: String
    let sessionID: String
    let cdpPort: Int?

    var brokerURL: String {
        "http://127.0.0.1:\(port)"
    }

    var cdpURL: String? {
        cdpPort.map { "http://127.0.0.1:\($0)" }
    }
}
