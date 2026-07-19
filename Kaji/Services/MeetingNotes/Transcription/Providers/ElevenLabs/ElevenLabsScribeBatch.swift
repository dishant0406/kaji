import Foundation

final class ElevenLabsScribeURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionElevenLabsScribeHTTPTransportFactory: ElevenLabsScribeHTTPTransportFactory {
    let policy: STTURLSessionPolicy

    func makeTransport() -> any ElevenLabsScribeHTTPTransporting {
        URLSessionElevenLabsScribeHTTPTransport(policy: policy)
    }
}

actor URLSessionElevenLabsScribeHTTPTransport: ElevenLabsScribeHTTPTransporting {
    private let delegate: ElevenLabsScribeURLSessionDelegate
    private let session: URLSession
    private let policy: STTURLSessionPolicy
    private var cancelled = false

    init(policy: STTURLSessionPolicy) {
        self.policy = policy
        let delegate = ElevenLabsScribeURLSessionDelegate()
        self.delegate = delegate
        session = URLSession(
            configuration: STTURLSessionConfigurationFactory.makeEphemeral(policy: policy),
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func execute(_ request: URLRequest, maximumResponseBytes: Int) async throws -> ElevenLabsScribeHTTPResponse {
        guard !cancelled,
              maximumResponseBytes >= 1,
              maximumResponseBytes <= policy.maximumResponseBytes
        else {
            throw cancelled ? ElevenLabsScribeError.providerFailure(
                code: "cancelled",
                classification: .cancelled,
                retryAfterMilliseconds: nil
            ) : ElevenLabsScribeError.invalidConfiguration("maximum-response-bytes")
        }
        var request = request
        STTRequestSecurity.apply(to: &request)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard !cancelled, let httpResponse = response as? HTTPURLResponse else {
                throw ElevenLabsScribeError.malformedResponse
            }
            guard httpResponse.expectedContentLength < 0 || httpResponse.expectedContentLength <= maximumResponseBytes
            else {
                throw ElevenLabsScribeError.responseTooLarge
            }
            var data = Data()
            data.reserveCapacity(min(maximumResponseBytes, max(0, Int(httpResponse.expectedContentLength))))
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else { throw ElevenLabsScribeError.responseTooLarge }
                data.append(byte)
            }
            guard !cancelled else {
                throw ElevenLabsScribeError.providerFailure(
                    code: "cancelled",
                    classification: .cancelled,
                    retryAfterMilliseconds: nil
                )
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                guard let key = pair.key as? String, let value = pair.value as? String else { return }
                result[key] = value
            }
            return try ElevenLabsScribeHTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: data
            )
        } catch let error as ElevenLabsScribeError {
            throw error
        } catch is CancellationError {
            throw ElevenLabsScribeError.providerFailure(
                code: "cancelled",
                classification: .cancelled,
                retryAfterMilliseconds: nil
            )
        } catch let error as URLError {
            let classification: MeetingTranscriptionFailureClassification = switch error.code {
            case .cancelled: .cancelled
            case .timedOut,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .notConnectedToInternet:
                .transient
            default: .unavailable
            }
            throw ElevenLabsScribeError.providerFailure(
                code: classification == .cancelled ? "cancelled" : "network-failure",
                classification: classification,
                retryAfterMilliseconds: nil
            )
        } catch {
            throw ElevenLabsScribeError.providerFailure(
                code: "network-failure",
                classification: .transient,
                retryAfterMilliseconds: nil
            )
        }
    }

    func cancel() {
        cancelled = true
        session.invalidateAndCancel()
    }
}

enum ElevenLabsScribeBatchDelivery: Equatable {
    case synchronous
    case configuredWebhook(webhookID: String?, metadata: [String: String])
}

struct ElevenLabsScribeBatchAcceptedJob: Equatable {
    let requestID: String
    let transcriptionID: String?
}

enum ElevenLabsScribeBatchResult: Equatable {
    case transcript(ElevenLabsScribeTranscript)
    case accepted(ElevenLabsScribeBatchAcceptedJob)
}

struct ElevenLabsScribeTranscript: Equatable {
    let languageCode: String
    let languageProbability: Double
    let text: String
    let words: [ElevenLabsScribeWord]
    let transcriptionID: String?
    let audioDurationSeconds: Double?
}

struct ElevenLabsScribeWord: Equatable {
    enum Kind: String {
        case word
        case spacing
        case audioEvent = "audio_event"
    }

    let text: String
    let startSeconds: Double?
    let endSeconds: Double?
    let kind: Kind
    let speakerID: String?
    let logProbability: Double
}

struct ElevenLabsScribeBatchRequest {
    let route: MeetingTranscriptionRoute
    let context: MeetingTrackTranscriptionContextSnapshot
    let packet: MeetingNormalizedAudioPacket
    let delivery: ElevenLabsScribeBatchDelivery
}

struct ElevenLabsScribeBatchClient {
    private let credentialResolver: any ElevenLabsScribeCredentialResolving
    private let transport: any ElevenLabsScribeHTTPTransporting
    private let options: ElevenLabsScribeBatchOptions
    private let endpoint: URL
    private let boundary: @Sendable () -> String

    init(
        credentialResolver: any ElevenLabsScribeCredentialResolving,
        transport: any ElevenLabsScribeHTTPTransporting,
        options: ElevenLabsScribeBatchOptions,
        endpoint: URL,
        boundary: @escaping @Sendable () -> String = { "KajiElevenLabs\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))" }
    ) {
        self.credentialResolver = credentialResolver
        self.transport = transport
        self.options = options
        self.endpoint = endpoint
        self.boundary = boundary
    }

    func submit(_ value: ElevenLabsScribeBatchRequest) async throws -> ElevenLabsScribeBatchResult {
        try validate(value)
        let apiKey = try await resolvedAPIKey()
        let url = try batchURL(endpoint: endpoint, retention: value.route.retention)
        let pcm16 = try ElevenLabsScribePCM16.packetData(value.packet)
        let wav = try STTMultipartWAVEncoder.wav(
            pcm16: pcm16,
            sampleRate: .hertz16000,
            maximumBytes: options.maximumWAVBytes
        )
        let multipartBoundary = boundary()
        let body = try ElevenLabsScribeMultipartBody.make(
            boundary: multipartBoundary,
            fields: fields(for: value),
            wav: wav,
            maximumBytes: options.maximumBodyBytes
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(multipartBoundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = body
        let response = try await transport.execute(request, maximumResponseBytes: options.maximumResponseBytes)
        try Self.validateContentType(response)
        guard response.statusCode == 200 else {
            throw Self.providerError(response)
        }
        switch value.delivery {
        case .synchronous:
            return try .transcript(ElevenLabsScribeBatchResponseParser.transcript(response.body))
        case .configuredWebhook:
            return try .accepted(ElevenLabsScribeBatchResponseParser.acceptedJob(response.body))
        }
    }

    private func validate(_ value: ElevenLabsScribeBatchRequest) throws {
        guard value.route.providerID == ElevenLabsScribeMeetingTranscriptionProvider.providerID,
              !value.route.modelID.isEmpty,
              value.route.mode == .cloudBatch,
              value.route.languageCodes.count <= 1,
              value.packet.sessionID == value.context.sessionID,
              value.packet.trackID == value.context.trackID,
              value.packet.source == value.context.source,
              value.packet.sampleRateHertz == 16000,
              value.packet.channelCount == 1,
              !value.packet.isEndOfStream,
              value.packet.sampleRange.frameCount >= 1600,
              value.packet.sampleRange.frameCount <= Int64(options.maximumAudioSeconds * 16000),
              options.speakerCount == nil || value.route.diarizationEnabled
        else {
            throw ElevenLabsScribeError.invalidPacket
        }
        try ElevenLabsScribeKeytermPolicy.validateBatch(value.context.keyterms)
        if case let .configuredWebhook(webhookID, metadata) = value.delivery {
            try validateWebhook(webhookID: webhookID, metadata: metadata)
        }
    }

    private func fields(for value: ElevenLabsScribeBatchRequest) throws -> [(String, String)] {
        var fields = [
            ("model_id", value.route.modelID),
            ("tag_audio_events", String(options.tagAudioEvents)),
            ("timestamps_granularity", "word"),
            ("diarize", String(value.route.diarizationEnabled)),
            ("no_verbatim", String(options.noVerbatim)),
        ]
        if let languageCode = value.route.languageCodes.first {
            fields.append(("language_code", languageCode))
        }
        if let speakerCount = options.speakerCount {
            fields.append(("num_speakers", String(speakerCount)))
        }
        fields.append(contentsOf: value.context.keyterms.map { ("keyterms", $0) })
        switch value.delivery {
        case .synchronous:
            fields.append(("webhook", "false"))
        case let .configuredWebhook(webhookID, metadata):
            fields.append(("webhook", "true"))
            if let webhookID { fields.append(("webhook_id", webhookID)) }
            if !metadata.isEmpty {
                let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
                guard let json = String(data: data, encoding: .utf8) else {
                    throw ElevenLabsScribeError.invalidConfiguration("webhook-metadata")
                }
                fields.append(("webhook_metadata", json))
            }
        }
        return fields
    }

    private func resolvedAPIKey() async throws -> String {
        let data: Data
        do {
            data = try await credentialResolver.resolveAPIKey()
        } catch let error as ElevenLabsScribeError {
            throw error
        } catch {
            throw ElevenLabsScribeError.credentialUnavailable
        }
        guard 1 ... 1024 ~= data.count,
              let value = String(data: data, encoding: .utf8),
              value.utf8.count == data.count,
              value.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E })
        else {
            throw ElevenLabsScribeError.invalidCredential
        }
        return value
    }

    private func batchURL(
        endpoint: URL,
        retention: MeetingTranscriptionDataRetentionClass
    ) throws -> URL {
        guard retention == .providerDefault || retention == .none || retention == .configurable,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else {
            throw ElevenLabsScribeError.invalidRoute
        }
        if retention != .configurable {
            let logging = URLQueryItem(
                name: "enable_logging",
                value: retention == .none ? "false" : "true"
            )
            components.queryItems = [logging]
        }
        guard let url = components.url else { throw ElevenLabsScribeError.invalidConfiguration("batch-url") }
        return url
    }

    private func validateWebhook(webhookID: String?, metadata: [String: String]) throws {
        guard webhookID.map(ElevenLabsScribeBatchResponseParser.isSafeProviderIdentifier) ?? true,
              metadata.count <= 64,
              metadata.allSatisfy({ key, value in
                  !key.isEmpty && key.utf8.count <= 128 && value.utf8.count <= 2000 &&
                      !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
                      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }),
              (try? JSONSerialization.data(withJSONObject: metadata).count) ?? Int.max <= 16 * 1024
        else {
            throw ElevenLabsScribeError.invalidConfiguration("webhook")
        }
    }

    private static func validateContentType(_ response: ElevenLabsScribeHTTPResponse) throws {
        guard let contentType = response.header("Content-Type")?.lowercased(),
              contentType.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ==
              "application/json"
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
    }

    static func providerError(_ response: ElevenLabsScribeHTTPResponse) -> ElevenLabsScribeError {
        let retryAfter = STTRetryAfterParser.delay(from: response.header("Retry-After")).map {
            Int64(($0 * 1000).rounded(.up))
        }
        let classification: MeetingTranscriptionFailureClassification = switch response.statusCode {
        case 400,
             405,
             409,
             415,
             422:
            .invalidRequest
        case 401: .authentication
        case 402: .quotaExceeded
        case 403: .authorization
        case 408,
             425,
             500,
             502,
             504:
            .transient
        case 429: .rateLimited
        case 503: .unavailable
        default: response.statusCode >= 500 ? .transient : .permanent
        }
        let parsedCode = ElevenLabsScribeBatchResponseParser.errorCode(response.body)
        return .providerFailure(
            code: parsedCode ?? "http-\(response.statusCode)",
            classification: classification,
            retryAfterMilliseconds: retryAfter
        )
    }
}

enum ElevenLabsScribePCM16 {
    static func packetData(_ packet: MeetingNormalizedAudioPacket) throws -> Data {
        guard packet.sampleRateHertz == 16000,
              packet.channelCount == 1,
              !packet.isEndOfStream
        else {
            throw ElevenLabsScribeError.invalidPacket
        }
        switch packet.encoding {
        case .pcmSigned16LittleEndian:
            guard packet.bytes.count == packet.sampleRange.frameCount * 2 else {
                throw ElevenLabsScribeError.invalidPacket
            }
            return packet.bytes
        case .pcmFloat32LittleEndian:
            guard packet.bytes.count == packet.sampleRange.frameCount * 4 else {
                throw ElevenLabsScribeError.invalidPacket
            }
            var data = Data(capacity: Int(packet.sampleRange.frameCount) * 2)
            try packet.bytes.withUnsafeBytes { bytes in
                for offset in stride(from: 0, to: bytes.count, by: 4) {
                    let bits = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                    let sample = Float(bitPattern: bits)
                    guard sample.isFinite else { throw ElevenLabsScribeError.invalidPacket }
                    let value: Int16 = if sample <= -1 {
                        .min
                    } else if sample >= 1 {
                        .max
                    } else {
                        Int16((sample * Float(Int16.max)).rounded())
                    }
                    var littleEndian = value.littleEndian
                    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
                }
            }
            return data
        default:
            throw ElevenLabsScribeError.invalidPacket
        }
    }
}

enum ElevenLabsScribeMultipartBody {
    static func make(
        boundary: String,
        fields: [(String, String)],
        wav: Data,
        maximumBytes: Int
    ) throws -> Data {
        guard isSafeToken(boundary, maximumLength: 70),
              fields.count <= 1100,
              wav.count <= ElevenLabsScribeBatchOptions.maximumSupportedWAVBytes
        else {
            throw ElevenLabsScribeError.invalidConfiguration("multipart")
        }
        var body = Data()
        for (name, value) in fields {
            guard isSafeToken(name, maximumLength: 64),
                  value.utf8.count <= 16 * 1024,
                  !value.contains("\r"),
                  !value.contains("\n"),
                  !value.contains("\0")
            else {
                throw ElevenLabsScribeError.invalidConfiguration("multipart-field")
            }
            try append(
                Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8),
                to: &body,
                maximumBytes: maximumBytes
            )
        }
        let fileHeader = Data(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8
        )
        try append(fileHeader, to: &body, maximumBytes: maximumBytes)
        try append(wav, to: &body, maximumBytes: maximumBytes)
        try append(Data("\r\n--\(boundary)--\r\n".utf8), to: &body, maximumBytes: maximumBytes)
        return body
    }

    private static func append(_ value: Data, to body: inout Data, maximumBytes: Int) throws {
        guard value.count <= maximumBytes - body.count else { throw ElevenLabsScribeError.requestTooLarge }
        body.append(value)
    }

    private static func isSafeToken(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return value.utf8.allSatisfy { byte in
            byte >= 0x41 && byte <= 0x5A ||
                byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 ||
                byte == 0x2D || byte == 0x5F
        }
    }
}

enum ElevenLabsScribeBatchResponseParser {
    static func transcript(_ data: Data) throws -> ElevenLabsScribeTranscript {
        let object = try dictionary(data)
        let allowed = Set([
            "language_code", "language_probability", "text", "words", "channel_index", "additional_formats",
            "transcription_id", "entities", "audio_duration_secs",
        ])
        guard Set(object.keys).isSubset(of: allowed),
              absentOrNull(object["channel_index"]),
              absentOrNull(object["additional_formats"]),
              absentOrNull(object["entities"]),
              let languageCode = object["language_code"] as? String,
              MeetingTranscriptionValidation.isValidLanguageCode(languageCode),
              let languageProbability = finiteDouble(object["language_probability"]),
              0 ... 1 ~= languageProbability,
              let text = boundedText(object["text"], maximumCharacters: 100_000)
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let rawWords: [Any]
        if object["words"] == nil || object["words"] is NSNull {
            rawWords = []
        } else if let values = object["words"] as? [Any], values.count <= 10000 {
            rawWords = values
        } else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let words = try rawWords.map(word)
        let transcriptionID = try optionalIdentifier(object["transcription_id"])
        let duration = try optionalFiniteDouble(object["audio_duration_secs"], range: 0 ... 36000)
        return ElevenLabsScribeTranscript(
            languageCode: languageCode,
            languageProbability: languageProbability,
            text: text,
            words: words,
            transcriptionID: transcriptionID,
            audioDurationSeconds: duration
        )
    }

    static func acceptedJob(_ data: Data) throws -> ElevenLabsScribeBatchAcceptedJob {
        let object = try dictionary(data)
        guard Set(object.keys).isSubset(of: ["message", "request_id", "transcription_id"]),
              let requestID = object["request_id"] as? String,
              isSafeProviderIdentifier(requestID),
              let message = object["message"] as? String,
              !message.isEmpty,
              message.count <= 1000
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return try ElevenLabsScribeBatchAcceptedJob(
            requestID: requestID,
            transcriptionID: optionalIdentifier(object["transcription_id"])
        )
    }

    static func errorCode(_ data: Data) -> String? {
        guard data.count <= 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] as? [String: Any],
              let code = detail["code"] as? String,
              isSafeProviderIdentifier(code)
        else {
            return nil
        }
        return code.replacingOccurrences(of: "_", with: "-")
    }

    static func isSafeProviderIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.utf8.allSatisfy { byte in
            byte >= 0x41 && byte <= 0x5A ||
                byte >= 0x61 && byte <= 0x7A ||
                byte >= 0x30 && byte <= 0x39 ||
                byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x3A
        }
    }

    private static func word(_ raw: Any) throws -> ElevenLabsScribeWord {
        guard let object = raw as? [String: Any],
              Set(object.keys).isSubset(of: [
                  "text", "start", "end", "type", "speaker_id", "logprob", "characters", "channel_index",
              ]),
              absentOrNull(object["characters"]),
              absentOrNull(object["channel_index"]),
              let text = object["text"] as? String,
              !text.isEmpty,
              text.count <= 1000,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let type = object["type"] as? String,
              let kind = ElevenLabsScribeWord.Kind(rawValue: type),
              let logProbability = finiteDouble(object["logprob"]),
              logProbability <= 0
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let start = try optionalFiniteDouble(object["start"], range: 0 ... 36000)
        let end = try optionalFiniteDouble(object["end"], range: 0 ... 36000)
        guard (start == nil) == (end == nil),
              (start.map { start in end.map { $0 >= start } ?? false } ?? (kind == .spacing))
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        let speakerID = try optionalIdentifier(object["speaker_id"])
        return ElevenLabsScribeWord(
            text: text,
            startSeconds: start,
            endSeconds: end,
            kind: kind,
            speakerID: speakerID,
            logProbability: logProbability
        )
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty,
              data.count <= 16 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return object
    }

    private static func boundedText(_ value: Any?, maximumCharacters: Int) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= maximumCharacters,
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" })
        else {
            return nil
        }
        return normalized
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func optionalFiniteDouble(
        _ value: Any?,
        range: ClosedRange<Double>
    ) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        guard let result = finiteDouble(value), range.contains(result) else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return result
    }

    private static func optionalIdentifier(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let result = value as? String, isSafeProviderIdentifier(result) else {
            throw ElevenLabsScribeError.malformedResponse
        }
        return result
    }

    private static func absentOrNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }
}
