enum NotificationDeliveryDecision {
    case persistAndDeliver
    case deliverOnly

    static func resolve(isAppActive: Bool, isTargetTabActive: Bool) -> Self {
        if isAppActive, isTargetTabActive {
            return .deliverOnly
        }
        return .persistAndDeliver
    }
}
