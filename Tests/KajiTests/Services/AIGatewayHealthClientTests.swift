import Foundation
import Testing

@testable import Kaji

@Suite("AI Gateway health client")
struct AIGatewayHealthClientTests {
    @Test("health status only passes when gateway is ready")
    func healthStatusRequiresRunningGateway() {
        #expect(AIGatewayHealthClient.isHealthyStatus(Data(#"{"status":"running"}"#.utf8)))
        #expect(AIGatewayHealthClient.isHealthyStatus(Data(#"{"status":"ok"}"#.utf8)))
        #expect(!AIGatewayHealthClient.isHealthyStatus(Data(#"{"status":"starting"}"#.utf8)))
        #expect(!AIGatewayHealthClient.isHealthyStatus(Data(#"{}"#.utf8)))
    }
}
