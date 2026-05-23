import CoreGraphics
import Foundation

struct MarkdownEditorScrollRequest {
    let tabID: UUID
    let scrollY: CGFloat
}

enum MarkdownEditorScrollBus {
    static let notificationName = Notification.Name("KajiMarkdownEditorScrollRequest")

    private static let tabIDKey = "tabID"
    private static let scrollYKey = "scrollY"

    static func publish(tabID: UUID, scrollY: CGFloat) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                tabIDKey: tabID,
                scrollYKey: scrollY,
            ]
        )
    }

    static func request(from notification: Notification) -> MarkdownEditorScrollRequest? {
        guard let userInfo = notification.userInfo,
              let tabID = userInfo[tabIDKey] as? UUID,
              let scrollY = userInfo[scrollYKey] as? CGFloat
        else { return nil }
        return MarkdownEditorScrollRequest(tabID: tabID, scrollY: scrollY)
    }
}
