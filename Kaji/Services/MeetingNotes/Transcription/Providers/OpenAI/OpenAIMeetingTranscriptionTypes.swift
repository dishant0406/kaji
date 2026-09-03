import Foundation

enum OpenAIMeetingTranscriptionError: Error, Equatable {
    case invalidConfiguration
    case invalidCredential
    case invalidRoute
    case invalidState
    case invalidPacket
    case audioBatchRequired
    case audioTooLarge
    case responseTooLarge
    case invalidResponse
    case rateLimited
    case authenticationFailed
    case authorizationFailed
    case quotaExceeded
    case serviceUnavailable
    case rotationRequired
    case cancelled
}

protocol OpenAICredentialSecretResolving: Sendable {
    func resolveSecret() async throws -> Data
}

protocol OpenAIAudioRateConverting: Sendable {
    func pcm16Mono24kHz(from packet: MeetingNormalizedAudioPacket) throws -> Data
}

struct OpenAIAlready24kHzAudioRateConverter: OpenAIAudioRateConverting {
    func pcm16Mono24kHz(from packet: MeetingNormalizedAudioPacket) throws -> Data {
        guard packet.encoding == .pcmSigned16LittleEndian,
              packet.sampleRateHertz == 24000,
              packet.channelCount == 1,
              packet.bytes.count.isMultiple(of: 2),
              !packet.bytes.isEmpty
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        return packet.bytes
    }
}

struct OpenAIPCM16AudioRateConverter: OpenAIAudioRateConverting {
    func pcm16Mono24kHz(from packet: MeetingNormalizedAudioPacket) throws -> Data {
        guard packet.encoding == .pcmSigned16LittleEndian,
              packet.channelCount == 1,
              packet.bytes.count.isMultiple(of: 2),
              !packet.bytes.isEmpty,
              packet.sampleRateHertz == 16000 || packet.sampleRateHertz == 24000
        else {
            throw OpenAIMeetingTranscriptionError.invalidPacket
        }
        if packet.sampleRateHertz == 24000 {
            return packet.bytes
        }
        let input = packet.bytes.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 2).map { offset in
                Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))
            }
        }
        let outputCount = input.count * 3 / 2
        guard outputCount > 0 else { throw OpenAIMeetingTranscriptionError.invalidPacket }
        var output = [Int16]()
        output.reserveCapacity(outputCount)
        for outputIndex in 0 ..< outputCount {
            let numerator = outputIndex * 2
            let lowerIndex = numerator / 3
            let remainder = numerator % 3
            let upperIndex = min(input.count - 1, lowerIndex + 1)
            let lower = Int64(input[lowerIndex])
            let upper = Int64(input[upperIndex])
            let interpolated = (lower * Int64(3 - remainder) + upper * Int64(remainder)) / 3
            output.append(Int16(clamping: interpolated))
        }
        return output.map(\.littleEndian).withUnsafeBytes { Data($0) }
    }
}

struct OpenAIHTTPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let finalURL: URL

    init(statusCode: Int, headers: [String: String], body: Data, finalURL: URL) throws {
        let normalizedHeaders = headers.map { ($0.key.lowercased(), $0.value) }
        guard 100 ... 599 ~= statusCode,
              headers.count <= 128,
              headers.allSatisfy({ key, value in
                  !key.isEmpty && key.utf8.count <= 256 && value.utf8.count <= 8192
              }),
              Set(normalizedHeaders.map(\.0)).count == normalizedHeaders.count
        else {
            throw OpenAIMeetingTranscriptionError.invalidResponse
        }
        self.statusCode = statusCode
        self.headers = Dictionary(uniqueKeysWithValues: normalizedHeaders)
        self.body = body
        self.finalURL = finalURL
    }
}

protocol OpenAIHTTPTransporting: Sendable {
    func execute(_ request: URLRequest) async throws -> OpenAIHTTPResponse
    func cancel() async
}

protocol OpenAIHTTPTransportFactory: Sendable {
    func makeTransport() -> any OpenAIHTTPTransporting
}

struct OpenAIMeetingTranscriptionConfiguration: Equatable {
    let streamBatchResponses: Bool
    let includeRealtimeLogprobs: Bool
    let maximumResponseBytes: Int
    let maximumRealtimeAudioBytesPerCommit: Int
    let realtimeBase64ChunkBytes: Int
    let realtimeDrainSeconds: TimeInterval

    init(
        streamBatchResponses: Bool = false,
        includeRealtimeLogprobs: Bool = false,
        maximumResponseBytes: Int = 8 * 1024 * 1024,
        maximumRealtimeAudioBytesPerCommit: Int = 8 * 1024 * 1024,
        realtimeBase64ChunkBytes: Int = 192 * 1024,
        realtimeDrainSeconds: TimeInterval = 10
    ) throws {
        guard 1 ... 16 * 1024 * 1024 ~= maximumResponseBytes,
              1 ... 16 * 1024 * 1024 ~= maximumRealtimeAudioBytesPerCommit,
              1 ... 256 * 1024 ~= realtimeBase64ChunkBytes,
              realtimeDrainSeconds.isFinite,
              0.1 ... 30 ~= realtimeDrainSeconds
        else {
            throw OpenAIMeetingTranscriptionError.invalidConfiguration
        }
        self.streamBatchResponses = streamBatchResponses
        self.includeRealtimeLogprobs = includeRealtimeLogprobs
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumRealtimeAudioBytesPerCommit = maximumRealtimeAudioBytesPerCommit
        self.realtimeBase64ChunkBytes = realtimeBase64ChunkBytes
        self.realtimeDrainSeconds = realtimeDrainSeconds
    }
}

enum OpenAICredentialValidator {
    static func bearerToken(from secret: Data) throws -> String {
        guard !secret.isEmpty,
              secret.count <= KeychainSTTCredentialProfileStore.maximumSecretBytes,
              let value = String(data: secret, encoding: .utf8),
              value.utf8.count == secret.count,
              value.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }),
              !value.contains(":")
        else {
            throw OpenAIMeetingTranscriptionError.invalidCredential
        }
        return value
    }
}

enum OpenAIStableIdentity {
    static func uuid(operationID: UUID, component: Int) -> UUID {
        var source = Data(operationID.uuidString.lowercased().utf8)
        source.append(Data(":\(component)".utf8))
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_119
        for byte in source {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 14_029_467_366_897_019_727
        }
        var bytes = withUnsafeBytes(of: first.bigEndian) { Array($0) }
        bytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian) { Array($0) })
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let value = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: value)
    }
}
