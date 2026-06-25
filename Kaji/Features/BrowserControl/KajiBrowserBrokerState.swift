import Foundation

struct KajiBrowserBrokerState: Equatable {
    let port: UInt16
    let token: String
    let sessionID: String

    var brokerURL: String {
        "http://127.0.0.1:\(port)"
    }
}
