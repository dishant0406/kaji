import Foundation

public let kajiPowerHelperMachServiceName = "com.kaji.app.power-helper"
public let kajiPowerHelperVersion = 1

@objc
public protocol KajiPowerHelperXPCProtocol {
    func setKeepAwake(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
    func getState(withReply reply: @escaping (Bool, Bool, String?) -> Void)
    func heartbeat(withReply reply: @escaping (Bool) -> Void)
    func version(withReply reply: @escaping (Int) -> Void)
    func restoreNow(withReply reply: @escaping (Bool, String?) -> Void)
}

public enum PMSetCommand: Equatable, Sendable {
    case readState
    case setSleepDisabled(Bool)

    public var executableURL: URL {
        URL(fileURLWithPath: "/usr/bin/pmset")
    }

    public var arguments: [String] {
        switch self {
        case .readState:
            ["-g"]
        case let .setSleepDisabled(disabled):
            ["-a", "disablesleep", disabled ? "1" : "0"]
        }
    }
}

public enum PMSetStateParser {
    public static func sleepDisabled(from output: String) -> Bool? {
        for line in output.split(whereSeparator: \Character.isNewline) {
            let fields = line.split(whereSeparator: \Character.isWhitespace)
            guard fields.count >= 2,
                  fields[fields.count - 2].caseInsensitiveCompare("SleepDisabled") == .orderedSame
            else {
                continue
            }
            switch fields.last {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }
        return nil
    }
}

public struct PowerHelperWatchdog: Sendable {
    public let timeout: TimeInterval
    public private(set) var lastHeartbeat: Date

    public init(timeout: TimeInterval = 15, now: Date = Date()) {
        self.timeout = min(max(timeout, 10), 30)
        lastHeartbeat = now
    }

    public mutating func heartbeat(at date: Date = Date()) {
        lastHeartbeat = date
    }

    public func shouldRestore(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(lastHeartbeat) >= timeout
    }
}

public enum PowerHelperRegistrationState: Equatable, Sendable {
    case unavailable
    case notRegistered
    case requiresApproval
    case registering
    case ready(sleepDisabled: Bool)
    case failed(String)
}

public enum PowerHelperServiceStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

public extension PowerHelperRegistrationState {
    static func resolve(status: PowerHelperServiceStatus, sleepDisabled: Bool = false) -> Self {
        switch status {
        case .enabled: .ready(sleepDisabled: sleepDisabled)
        case .requiresApproval: .requiresApproval
        case .notRegistered,
             .notFound: .notRegistered
        case .unknown: .unavailable
        }
    }
}

public enum PowerHelperError: LocalizedError, Equatable, Sendable {
    case unavailable
    case notRegistered
    case requiresApproval
    case connectionFailed
    case commandFailed(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Power Protect is unavailable on this system."
        case .notRegistered: "Power Protect is not registered."
        case .requiresApproval: "Power Protect requires approval in System Settings."
        case .connectionFailed: "The Power Protect helper could not be reached."
        case let .commandFailed(message): message
        case .verificationFailed: "The requested power state could not be verified."
        }
    }
}
