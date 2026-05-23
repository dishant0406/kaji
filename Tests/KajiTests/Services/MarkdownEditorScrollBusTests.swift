import CoreGraphics
import Foundation
import Testing

@testable import Kaji

@Suite("MarkdownEditorScrollBus")
struct MarkdownEditorScrollBusTests {
    @Test("decodes scroll request notification")
    func decodesScrollRequestNotification() throws {
        let tabID = UUID()
        let notification = Notification(
            name: MarkdownEditorScrollBus.notificationName,
            userInfo: [
                "tabID": tabID,
                "scrollY": CGFloat(42),
            ]
        )

        let request = try #require(MarkdownEditorScrollBus.request(from: notification))

        #expect(request.tabID == tabID)
        #expect(request.scrollY == 42)
    }
}
