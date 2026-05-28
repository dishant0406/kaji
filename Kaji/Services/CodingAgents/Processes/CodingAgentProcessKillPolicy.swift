import Darwin
import Foundation

enum CodingAgentProcessKillPolicyError: LocalizedError, Equatable {
    case invalidPID
    case currentProcess
    case parentProcess
    case systemProcess

    var errorDescription: String? {
        switch self {
        case .invalidPID:
            "Invalid process id."
        case .currentProcess:
            "Kaji cannot kill its own process."
        case .parentProcess:
            "Kaji cannot kill its parent process."
        case .systemProcess:
            "Kaji cannot kill system processes."
        }
    }
}

enum CodingAgentProcessKillPolicy {
    static func validate(pid: Int32, currentPID: Int32 = getpid(), parentPID: Int32 = getppid()) -> CodingAgentProcessKillPolicyError? {
        guard pid > 0 else { return .invalidPID }
        guard pid > 1 else { return .systemProcess }
        guard pid != currentPID else { return .currentProcess }
        guard pid != parentPID else { return .parentProcess }
        return nil
    }
}
