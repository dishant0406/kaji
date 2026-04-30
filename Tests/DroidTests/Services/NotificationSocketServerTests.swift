import Foundation
import Testing

@testable import Droid

struct NotificationSocketServerTests {
    @Test
    func socketPathIsProcessSpecific() {
        let processID = ProcessInfo.processInfo.processIdentifier

        #expect(NotificationSocketServer.socketPath.hasSuffix("droid-\(processID).sock"))
    }
}
