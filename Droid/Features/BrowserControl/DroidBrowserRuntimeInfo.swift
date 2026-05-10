import Foundation

struct DroidBrowserRuntimeInfo: Equatable {
    let rootPath: String
    let profilePath: String
    let helperPath: String
    let remoteDebuggingPort: Int

    var cdpURL: String {
        "http://127.0.0.1:\(remoteDebuggingPort)"
    }
}
