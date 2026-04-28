import Foundation

struct NotificationSocketRecoveryPolicy {
    static let retryDelaySeconds: Double = 2
    static let healthCheckIntervalSeconds: Double = 15

    static func shouldRecover(
        wantsListening: Bool,
        socketExists: Bool,
        hasAcceptSource: Bool,
        serverFD: Int32
    ) -> Bool {
        guard wantsListening else { return false }
        guard socketExists else { return true }
        guard hasAcceptSource else { return true }
        return serverFD < 0
    }

    static func shouldRetryAfterAcceptFailure(errno: Int32) -> Bool {
        errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR
    }
}
