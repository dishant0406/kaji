import Foundation

enum DroidCodeGraphEnvironmentTestLock {
    private static let storage = NSLock()

    static func lock() {
        storage.lock()
    }

    static func unlock() {
        storage.unlock()
    }
}
