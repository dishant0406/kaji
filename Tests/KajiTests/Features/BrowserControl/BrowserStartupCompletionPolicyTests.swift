import Foundation
import Testing

@testable import Kaji

struct BrowserStartupCompletionPolicyTests {
    @Test
    func controllerCloseDoesNotMarkStartupWhenRuntimeNeverStarted() {
        #expect(!BrowserStartupCompletionPolicy.shouldMarkStartedWhenControllerCloses(runtimeInfo: nil))
    }

    @Test
    func controllerCloseMarksStartupWhenRuntimeStarted() {
        let runtimeInfo = KajiBrowserRuntimeInfo(
            rootPath: "/runtime",
            profilePath: "/profile",
            helperPath: "/helper",
            remoteDebuggingPort: 9222
        )

        #expect(BrowserStartupCompletionPolicy.shouldMarkStartedWhenControllerCloses(runtimeInfo: runtimeInfo))
    }
}
