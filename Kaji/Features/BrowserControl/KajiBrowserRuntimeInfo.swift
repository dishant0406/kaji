import Foundation

struct KajiBrowserRuntimeInfo: Equatable {
    let rootPath: String
    let profilePath: String
    let rootCachePath: String
    let helperPath: String
    let remoteDebuggingPort: Int

    var cdpURL: String {
        "http://127.0.0.1:\(remoteDebuggingPort)"
    }
}
