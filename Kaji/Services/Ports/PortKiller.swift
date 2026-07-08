import Darwin
import Foundation

enum PortKillError: LocalizedError {
    case blocked(PortKillPolicyError)
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .blocked(error):
            error.localizedDescription
        case let .signalFailed(code):
            String(cString: strerror(code))
        }
    }
}

enum PortKiller {
    static func terminate(pid: Int32) throws {
        try send(SIGTERM, to: pid)
    }

    static func kill(pid: Int32) throws {
        try send(SIGKILL, to: pid)
    }

    private static func send(_ signal: Int32, to pid: Int32) throws {
        if let error = PortKillPolicy.validate(pid: pid) {
            throw PortKillError.blocked(error)
        }
        guard Darwin.kill(pid, signal) == 0 else {
            throw PortKillError.signalFailed(errno)
        }
    }
}
