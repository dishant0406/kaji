import Foundation

enum STTSSEDecoderError: Error, Equatable {
    case invalidEncoding
    case lineTooLong
    case eventTooLarge
    case bufferTooLarge
    case tooManyEvents
}

struct STTServerSentEvent: Equatable {
    let event: String?
    let data: String
    let id: String?
    let retryMilliseconds: Int?
}

struct STTSSEDecoderLimits: Equatable {
    let maximumLineBytes: Int
    let maximumEventDataBytes: Int
    let maximumBufferedBytes: Int
    let maximumEventsPerBatch: Int

    init(
        maximumLineBytes: Int = 16 * 1024,
        maximumEventDataBytes: Int = 1024 * 1024,
        maximumBufferedBytes: Int = 2 * 1024 * 1024,
        maximumEventsPerBatch: Int = 256
    ) throws {
        guard maximumLineBytes >= 1,
              maximumEventDataBytes >= maximumLineBytes,
              maximumBufferedBytes >= maximumEventDataBytes,
              maximumBufferedBytes <= 16 * 1024 * 1024,
              maximumEventsPerBatch >= 1,
              maximumEventsPerBatch <= 4096
        else {
            throw STTNetworkError.invalidConfiguration
        }
        self.maximumLineBytes = maximumLineBytes
        self.maximumEventDataBytes = maximumEventDataBytes
        self.maximumBufferedBytes = maximumBufferedBytes
        self.maximumEventsPerBatch = maximumEventsPerBatch
    }
}

struct STTServerSentEventDecoder {
    let limits: STTSSEDecoderLimits
    private var buffer = Data()
    private var eventName: String?
    private var dataLines: [String] = []
    private var dataByteCount = 0
    private var eventID: String?
    private var retryMilliseconds: Int?

    init(limits: STTSSEDecoderLimits) {
        self.limits = limits
    }

    mutating func append(_ chunk: Data) throws -> [STTServerSentEvent] {
        guard chunk.count <= limits.maximumBufferedBytes - buffer.count else {
            reset()
            throw STTSSEDecoderError.bufferTooLarge
        }
        buffer.append(chunk)
        var events: [STTServerSentEvent] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer[..<newlineIndex]
            if line.last == 0x0D {
                line = line.dropLast()
            }
            guard line.count <= limits.maximumLineBytes else {
                reset()
                throw STTSSEDecoderError.lineTooLong
            }
            let lineData = Data(line)
            buffer.removeSubrange(...newlineIndex)
            if let event = try process(lineData) {
                events.append(event)
                guard events.count <= limits.maximumEventsPerBatch else {
                    reset()
                    throw STTSSEDecoderError.tooManyEvents
                }
            }
        }
        guard buffer.count <= limits.maximumLineBytes else {
            reset()
            throw STTSSEDecoderError.lineTooLong
        }
        return events
    }

    mutating func finish() throws -> [STTServerSentEvent] {
        var events: [STTServerSentEvent] = []
        if !buffer.isEmpty {
            guard buffer.count <= limits.maximumLineBytes else {
                reset()
                throw STTSSEDecoderError.lineTooLong
            }
            if let event = try process(buffer) {
                events.append(event)
            }
            buffer.removeAll(keepingCapacity: false)
        }
        if let event = dispatch() {
            events.append(event)
        }
        guard events.count <= limits.maximumEventsPerBatch else {
            reset()
            throw STTSSEDecoderError.tooManyEvents
        }
        return events
    }

    private mutating func process(_ lineData: Data) throws -> STTServerSentEvent? {
        guard let line = String(data: lineData, encoding: .utf8) else {
            reset()
            throw STTSSEDecoderError.invalidEncoding
        }
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        switch field {
        case "event":
            guard value.utf8.count <= limits.maximumLineBytes, !value.contains("\0") else {
                throw STTSSEDecoderError.eventTooLarge
            }
            eventName = value
        case "data":
            let addedBytes = value.utf8.count + (dataLines.isEmpty ? 0 : 1)
            guard addedBytes <= limits.maximumEventDataBytes - dataByteCount else {
                resetEvent()
                throw STTSSEDecoderError.eventTooLarge
            }
            dataLines.append(value)
            dataByteCount += addedBytes
        case "id":
            guard value.utf8.count <= limits.maximumLineBytes, !value.contains("\0") else {
                throw STTSSEDecoderError.eventTooLarge
            }
            eventID = value
        case "retry":
            if value.allSatisfy(\.isNumber), let parsed = Int(value), parsed >= 0 {
                retryMilliseconds = parsed
            }
        default:
            break
        }
        return nil
    }

    private mutating func dispatch() -> STTServerSentEvent? {
        guard !dataLines.isEmpty else {
            resetEvent()
            return nil
        }
        let event = STTServerSentEvent(
            event: eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventID,
            retryMilliseconds: retryMilliseconds
        )
        resetEvent()
        return event
    }

    private mutating func resetEvent() {
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
        dataByteCount = 0
        eventID = nil
        retryMilliseconds = nil
    }

    private mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        resetEvent()
    }
}
