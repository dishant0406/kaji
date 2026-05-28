import Darwin
import Foundation

enum CodingAgentProcessKillError: LocalizedError {
    case blocked(CodingAgentProcessKillPolicyError)
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

enum CodingAgentProcessKiller {
    static func terminate(pid: Int32) throws {
        try signal(pid: pid, value: SIGTERM)
    }

    static func forceTerminate(pid: Int32) throws {
        try signal(pid: pid, value: SIGKILL)
    }

    private static func signal(pid: Int32, value: Int32) throws {
        if let error = CodingAgentProcessKillPolicy.validate(pid: pid) {
            throw CodingAgentProcessKillError.blocked(error)
        }
        guard kill(pid, value) == 0 else {
            throw CodingAgentProcessKillError.signalFailed(errno)
        }
    }
}
