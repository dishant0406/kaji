import Foundation
import Testing

@testable import Droid

struct NotificationSocketRecoveryPolicyTests {
    @Test
    func recoverWhenSocketIsMissing() {
        #expect(
            NotificationSocketRecoveryPolicy.shouldRecover(
                wantsListening: true,
                socketExists: false,
                hasAcceptSource: true,
                serverFD: 7
            )
        )
    }

    @Test
    func recoverWhenListenerIsGone() {
        #expect(
            NotificationSocketRecoveryPolicy.shouldRecover(
                wantsListening: true,
                socketExists: true,
                hasAcceptSource: false,
                serverFD: 7
            )
        )
    }

    @Test
    func ignoreRecoveryWhenStopped() {
        #expect(
            !NotificationSocketRecoveryPolicy.shouldRecover(
                wantsListening: false,
                socketExists: false,
                hasAcceptSource: false,
                serverFD: -1
            )
        )
    }

    @Test
    func acceptRetryIgnoresTransientErrnos() {
        #expect(!NotificationSocketRecoveryPolicy.shouldRetryAfterAcceptFailure(errno: EAGAIN))
        #expect(!NotificationSocketRecoveryPolicy.shouldRetryAfterAcceptFailure(errno: EWOULDBLOCK))
        #expect(!NotificationSocketRecoveryPolicy.shouldRetryAfterAcceptFailure(errno: EINTR))
        #expect(NotificationSocketRecoveryPolicy.shouldRetryAfterAcceptFailure(errno: EBADF))
    }
}
