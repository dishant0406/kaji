import Foundation
import os

enum GhosttyPerf {
    private static let log = OSLog(subsystem: "app.kaji", category: "GhosttyPerf")
    private static let logger = Logger(subsystem: "app.kaji", category: "GhosttyPerf")

    static func begin(_ name: StaticString, _ message: @autoclosure () -> String = "") -> OSSignpostID {
        let id = OSSignpostID(log: log)
        if message().isEmpty {
            os_signpost(.begin, log: log, name: name, signpostID: id)
        } else {
            os_signpost(.begin, log: log, name: name, signpostID: id, "%{public}s", message())
        }
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID, _ message: @autoclosure () -> String = "") {
        if message().isEmpty {
            os_signpost(.end, log: log, name: name, signpostID: id)
        } else {
            os_signpost(.end, log: log, name: name, signpostID: id, "%{public}s", message())
        }
    }

    static func event(_ name: StaticString, _ message: @autoclosure () -> String = "") {
        if message().isEmpty {
            os_signpost(.event, log: log, name: name)
        } else {
            os_signpost(.event, log: log, name: name, "%{public}s", message())
        }
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
