import Foundation

enum BrowserStartupCompletionPolicy {
    static func shouldMarkStartedWhenControllerCloses(runtimeInfo: KajiBrowserRuntimeInfo?) -> Bool {
        runtimeInfo != nil
    }
}
