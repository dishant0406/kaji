enum NotificationDeliveryDecision {
    case persistUnreadAndDeliver
    case persistReadAndDeliver

    static func resolve(isAppActive: Bool, isTargetTabActive: Bool) -> Self {
        if isAppActive, isTargetTabActive {
            return .persistReadAndDeliver
        }
        return .persistUnreadAndDeliver
    }
}
