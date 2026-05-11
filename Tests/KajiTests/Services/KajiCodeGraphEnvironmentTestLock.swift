import Foundation

enum KajiCodeGraphEnvironmentTestLock {
    private static let storage = NSLock()

    static func lock() {
        storage.lock()
    }

    static func unlock() {
        storage.unlock()
    }
}
