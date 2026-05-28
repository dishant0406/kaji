import Darwin
import Foundation

enum PortKillPolicyError: LocalizedError, Equatable {
    case invalidPID
    case currentProcess
    case parentProcess

    var errorDescription: String? {
        switch self {
        case .invalidPID:
            "Invalid process id."
        case .currentProcess:
            "Kaji cannot kill its own process."
        case .parentProcess:
            "Kaji cannot kill its parent process."
        }
    }
}

enum PortKillPolicy {
    static func validate(pid: Int32, currentPID: Int32 = getpid(), parentPID: Int32 = getppid()) -> PortKillPolicyError? {
        guard pid > 0 else { return .invalidPID }
        guard pid != currentPID else { return .currentProcess }
        guard pid != parentPID else { return .parentProcess }
        return nil
    }
}
