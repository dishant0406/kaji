import Darwin
import Foundation
import IOKit

public let closedLidGuardMaximumFrameBytes = 4096
public let closedLidGuardDefaultHeartbeatTimeout: TimeInterval = 15

public struct ClosedLidStandardSessionEvidence: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let armedMonotonicNanoseconds: UInt64
    public let lastHeartbeatMonotonicNanoseconds: UInt64
    public let heartbeatCount: UInt64

    public init(
        sessionID: UUID,
        armedMonotonicNanoseconds: UInt64,
        lastHeartbeatMonotonicNanoseconds: UInt64,
        heartbeatCount: UInt64
    ) {
        self.sessionID = sessionID
        self.armedMonotonicNanoseconds = armedMonotonicNanoseconds
        self.lastHeartbeatMonotonicNanoseconds = lastHeartbeatMonotonicNanoseconds
        self.heartbeatCount = heartbeatCount
    }
}

public enum ClosedLidGuardCommand: String, Codable, Sendable {
    case arm
    case disarm
    case heartbeat
    case status
    case shutdown
}

public struct ClosedLidGuardRequest: Codable, Sendable, Equatable {
    public let id: UUID
    public let command: ClosedLidGuardCommand

    public init(id: UUID = UUID(), command: ClosedLidGuardCommand) {
        self.id = id
        self.command = command
    }
}

public enum ClosedLidGuardState: String, Codable, Sendable, Equatable {
    case disarmed
    case armed
}

public struct ClosedLidGuardResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let state: ClosedLidGuardState
    public let selectorResult: kern_return_t
    public let evidence: ClosedLidStandardSessionEvidence?
    public let shouldExit: Bool

    public init(
        id: UUID,
        state: ClosedLidGuardState,
        selectorResult: kern_return_t,
        evidence: ClosedLidStandardSessionEvidence?,
        shouldExit: Bool = false
    ) {
        self.id = id
        self.state = state
        self.selectorResult = selectorResult
        self.evidence = evidence
        self.shouldExit = shouldExit
    }
}

public enum ClosedLidGuardProtocolError: Error, Equatable {
    case frameTooLarge
    case endOfFile
    case timedOut
    case ioFailure(Int32)
}

public struct ClosedLidJSONLineReader {
    private let descriptor: Int32
    private let maximumBytes: Int
    private var buffer = Data()

    public init(descriptor: Int32, maximumBytes: Int = closedLidGuardMaximumFrameBytes) {
        self.descriptor = descriptor
        self.maximumBytes = maximumBytes
    }

    public mutating func nextFrame(timeout: TimeInterval?) throws -> Data {
        let deadline = timeout.map { DispatchTime.now().uptimeNanoseconds + UInt64(max($0, 0.001) * 1_000_000_000) }
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let frame = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard frame.count <= maximumBytes else { throw ClosedLidGuardProtocolError.frameTooLarge }
                return Data(frame)
            }
            guard buffer.count <= maximumBytes else { throw ClosedLidGuardProtocolError.frameTooLarge }
            let timeoutMilliseconds: Int32
            if let deadline {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline else { throw ClosedLidGuardProtocolError.timedOut }
                timeoutMilliseconds = Int32(min(max((deadline - now) / 1_000_000, 1), UInt64(Int32.max)))
            } else {
                timeoutMilliseconds = -1
            }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
            if pollResult == 0 {
                throw ClosedLidGuardProtocolError.timedOut
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw ClosedLidGuardProtocolError.ioFailure(errno)
            }
            guard pollDescriptor.revents & Int16(POLLERR | POLLNVAL) == 0 else {
                throw ClosedLidGuardProtocolError.ioFailure(EIO)
            }
            let capacity = min(1024, maximumBytes + 1 - buffer.count)
            var bytes = [UInt8](repeating: 0, count: capacity)
            let count = Darwin.read(descriptor, &bytes, capacity)
            if count == 0 {
                throw ClosedLidGuardProtocolError.endOfFile
            }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                throw ClosedLidGuardProtocolError.ioFailure(errno)
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}

public enum ClosedLidJSONLineCodec {
    public static func encode(_ value: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(value)
        guard data.count <= closedLidGuardMaximumFrameBytes else { throw ClosedLidGuardProtocolError.frameTooLarge }
        data.append(0x0A)
        return data
    }
}
