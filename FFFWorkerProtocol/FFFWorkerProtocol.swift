import Darwin
import Foundation

public let fffWorkerMaximumRequestBytes = 1_048_576
public let fffWorkerMaximumResponseBytes = 16_777_216

public struct FFFWorkerRequest: Codable, Sendable, Equatable {
    public let id: UUID
    public let command: FFFWorkerCommand

    public init(id: UUID = UUID(), command: FFFWorkerCommand) {
        self.id = id
        self.command = command
    }
}

public enum FFFWorkerCommand: Codable, Sendable, Equatable {
    case create(projectPath: String, databasePath: String)
    case warm(projectPath: String, timeoutMilliseconds: UInt64)
    case searchFiles(projectPath: String, query: String, limit: Int)
    case searchText(projectPath: String, query: String, limit: Int)
    case remove(projectPath: String)
    case shutdown
}

public struct FFFWorkerResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let result: FFFWorkerResult?
    public let error: FFFWorkerFailure?

    public init(id: UUID, result: FFFWorkerResult) {
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: UUID, error: FFFWorkerFailure) {
        self.id = id
        self.result = nil
        self.error = error
    }
}

public enum FFFWorkerResult: Codable, Sendable, Equatable {
    case acknowledged
    case files([FFFWorkerFileResult])
    case textMatches([FFFWorkerTextMatch])
}

public struct FFFWorkerFileResult: Codable, Sendable, Equatable {
    public let relativePath: String
    public let fileName: String

    public init(relativePath: String, fileName: String) {
        self.relativePath = relativePath
        self.fileName = fileName
    }
}

public struct FFFWorkerTextMatch: Codable, Sendable, Equatable {
    public let relativePath: String
    public let lineContent: String
    public let lineNumber: UInt64
    public let column: UInt32

    public init(relativePath: String, lineContent: String, lineNumber: UInt64, column: UInt32) {
        self.relativePath = relativePath
        self.lineContent = lineContent
        self.lineNumber = lineNumber
        self.column = column
    }
}

public struct FFFWorkerFailure: Codable, Sendable, Equatable {
    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = String(message.prefix(2048))
    }

    public enum Code: String, Codable, Sendable {
        case invalidRequest
        case indexUnavailable
        case searchFailed
        case internalFailure
    }
}

public enum FFFWorkerProtocolError: Error, Equatable {
    case frameTooLarge
    case endOfFile
    case timedOut
    case ioFailure(Int32)
}

public struct FFFJSONLineReader {
    private let handle: FileHandle
    private let maximumBytes: Int
    private var buffer = Data()

    public init(handle: FileHandle, maximumBytes: Int) {
        self.handle = handle
        self.maximumBytes = maximumBytes
    }

    public mutating func nextFrame(timeout: TimeInterval? = nil) throws -> Data {
        let clock = ContinuousClock()
        let deadline = timeout.map { clock.now.advanced(by: .milliseconds(Int64(max(1, $0 * 1000)))) }
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let frame = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard frame.count <= maximumBytes else { throw FFFWorkerProtocolError.frameTooLarge }
                return Data(frame)
            }
            guard buffer.count <= maximumBytes else { throw FFFWorkerProtocolError.frameTooLarge }
            let waitMilliseconds: Int32
            if let deadline {
                let remaining = clock.now.duration(to: deadline)
                guard remaining > .zero else { throw FFFWorkerProtocolError.timedOut }
                let components = remaining.components
                let milliseconds = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
                waitMilliseconds = Int32(min(max(milliseconds, 1), Int64(Int32.max)))
            } else {
                waitMilliseconds = -1
            }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, waitMilliseconds)
            if pollResult == 0 {
                throw FFFWorkerProtocolError.timedOut
            }
            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                throw FFFWorkerProtocolError.ioFailure(errno)
            }
            guard descriptor.revents & Int16(POLLERR | POLLNVAL) == 0 else {
                throw FFFWorkerProtocolError.ioFailure(EIO)
            }
            let capacity = min(4096, maximumBytes + 1 - buffer.count)
            var bytes = [UInt8](repeating: 0, count: capacity)
            let count = Darwin.read(handle.fileDescriptor, &bytes, capacity)
            if count == 0 {
                throw FFFWorkerProtocolError.endOfFile
            }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                throw FFFWorkerProtocolError.ioFailure(errno)
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}

public enum FFFJSONLineCodec {
    public static func encode(_ value: some Encodable, maximumBytes: Int) throws -> Data {
        var data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw FFFWorkerProtocolError.frameTooLarge }
        data.append(0x0A)
        return data
    }
}
