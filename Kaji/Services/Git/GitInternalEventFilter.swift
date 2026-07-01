import CoreServices
import Foundation

enum GitInternalEventFilter {
    static func isDominated(events: [(String, UInt32)]) -> Bool {
        events.allSatisfy { path, flag in
            let isGitInternal = path.contains("/.git/")
            let isLockFile = path.hasSuffix(".lock")
            let isDirectory = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            return isGitInternal && isLockFile || isDirectory && isGitInternal
        }
    }
}
