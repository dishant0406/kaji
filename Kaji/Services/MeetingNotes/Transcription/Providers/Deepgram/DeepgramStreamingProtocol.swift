import Foundation

struct DeepgramStreamingWord: Equatable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
    let speaker: Int?
    let speakerConfidence: Double?
    let language: String?
}

struct DeepgramStreamingResult: Equatable {
    let channelIndex: Int
    let start: Double
    let duration: Double
    let isFinal: Bool
    let speechFinal: Bool
    let transcript: String
    let confidence: Double
    let languages: [String]
    let words: [DeepgramStreamingWord]
}

struct DeepgramStreamingMetadata: Equatable {
    let requestID: String
    let duration: Double
    let channels: Int
}

struct DeepgramStreamingProviderNotice: Equatable {
    let code: String
    let statusCode: Int?
    let retryAfterMilliseconds: Int64?
}

struct DeepgramStreamingRateLimit: Equatable {
    let scope: String
    let limit: Int64?
    let remaining: Int64?
    let resetsAtMilliseconds: Int64?
    let retryAfterMilliseconds: Int64?
}

enum DeepgramStreamingServerEvent: Equatable {
    case results(DeepgramStreamingResult)
    case metadata(DeepgramStreamingMetadata)
    case speechStarted(timestamp: Double)
    case utteranceEnd(lastWordEnd: Double)
    case warning(DeepgramStreamingProviderNotice)
    case error(DeepgramStreamingProviderNotice)
    case rateLimit(DeepgramStreamingRateLimit)
}

enum DeepgramStreamingEventDecoder {
    static func decode(_ text: String) throws -> DeepgramStreamingServerEvent {
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let value = try JSONSerialization.jsonObject(with: data, options: [])
        guard let object = value as? [String: Any] else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        if object["type"] == nil, object["err_code"] != nil || object["error_code"] != nil {
            return try .error(notice(object, expectedType: nil))
        }
        let type = try string(object, "type", maximumBytes: 64)
        switch type {
        case "Results":
            return try .results(result(object))
        case "Metadata":
            return try .metadata(metadata(object))
        case "SpeechStarted":
            try keys(object, allowed: ["type", "channel", "timestamp"])
            return try .speechStarted(timestamp: finiteNonnegativeDouble(object, "timestamp"))
        case "UtteranceEnd":
            try keys(object, allowed: ["type", "channel", "last_word_end"])
            guard let lastWordEnd = try optionalDouble(object, "last_word_end"),
                  lastWordEnd == -1 || lastWordEnd >= 0
            else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return .utteranceEnd(lastWordEnd: lastWordEnd)
        case "Warning":
            return try .warning(notice(object, expectedType: "Warning"))
        case "Error":
            return try .error(notice(object, expectedType: "Error"))
        case "RateLimit",
             "RateLimitWarning":
            return try .rateLimit(rateLimit(object))
        default:
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
    }

    private static func result(_ object: [String: Any]) throws -> DeepgramStreamingResult {
        try keys(object, allowed: [
            "type", "channel_index", "duration", "start", "is_final", "speech_final", "channel", "metadata",
            "from_finalize", "entities",
        ])
        let indexes = try integerArray(object, "channel_index", maximumCount: 2)
        guard let channelIndex = indexes.first else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let channel = try dictionary(object, "channel")
        try keys(channel, allowed: ["alternatives", "detected_language", "language_confidence"])
        let alternatives = try dictionaryArray(channel, "alternatives", maximumCount: 10)
        guard let alternative = alternatives.first else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        try keys(alternative, allowed: ["transcript", "confidence", "languages", "words"])
        let rawWords = try dictionaryArray(alternative, "words", maximumCount: 10000)
        let words = try rawWords.map { word -> DeepgramStreamingWord in
            try keys(word, allowed: [
                "word", "punctuated_word", "start", "end", "confidence", "speaker", "speaker_confidence", "language",
            ])
            let start = try finiteNonnegativeDouble(word, "start")
            let end = try finiteNonnegativeDouble(word, "end")
            let confidence = try probability(word, "confidence")
            guard end > start else { throw DeepgramMeetingTranscriptionError.protocolViolation }
            let text = try optionalString(word, "punctuated_word", maximumBytes: 4000)
                ?? string(word, "word", maximumBytes: 4000)
            let speaker = try optionalInteger(word, "speaker")
            guard speaker.map({ 0 ... 9999 ~= $0 }) ?? true else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            let language = try optionalString(word, "language", maximumBytes: 32)
            guard language.map(MeetingTranscriptionValidation.isValidLanguageCode) ?? true else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return try DeepgramStreamingWord(
                text: text,
                start: start,
                end: end,
                confidence: confidence,
                speaker: speaker,
                speakerConfidence: optionalProbability(word, "speaker_confidence"),
                language: language
            )
        }
        let languages = try optionalStringArray(alternative, "languages", maximumCount: 16) ?? []
        guard languages.allSatisfy(MeetingTranscriptionValidation.isValidLanguageCode) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        if let metadata = object["metadata"] as? [String: Any] {
            try resultMetadata(metadata)
        } else if object["metadata"] != nil {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        if let entities = object["entities"] {
            guard let values = entities as? [Any], values.count <= 10000 else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
        }
        return try DeepgramStreamingResult(
            channelIndex: channelIndex,
            start: finiteNonnegativeDouble(object, "start"),
            duration: finiteNonnegativeDouble(object, "duration"),
            isFinal: optionalBoolean(object, "is_final") ?? false,
            speechFinal: optionalBoolean(object, "speech_final") ?? false,
            transcript: string(alternative, "transcript", maximumBytes: 400_000),
            confidence: probability(alternative, "confidence"),
            languages: languages,
            words: words
        )
    }

    private static func resultMetadata(_ object: [String: Any]) throws {
        try keys(object, allowed: ["request_id", "model_info", "model_uuid"])
        _ = try string(object, "request_id", maximumBytes: 128)
        _ = try string(object, "model_uuid", maximumBytes: 128)
        let modelInfo = try dictionary(object, "model_info")
        try keys(modelInfo, allowed: ["name", "version", "arch"])
        _ = try string(modelInfo, "name", maximumBytes: 128)
        _ = try string(modelInfo, "version", maximumBytes: 128)
        _ = try string(modelInfo, "arch", maximumBytes: 128)
    }

    private static func metadata(_ object: [String: Any]) throws -> DeepgramStreamingMetadata {
        try keys(object, allowed: [
            "type", "transaction_key", "request_id", "sha256", "created", "duration", "channels", "models", "model_info",
        ])
        let channels = try integer(object, "channels")
        guard 0 ... 32 ~= channels else { throw DeepgramMeetingTranscriptionError.protocolViolation }
        return try DeepgramStreamingMetadata(
            requestID: string(object, "request_id", maximumBytes: 128),
            duration: finiteNonnegativeDouble(object, "duration"),
            channels: channels
        )
    }

    private static func notice(
        _ object: [String: Any],
        expectedType: String?
    ) throws -> DeepgramStreamingProviderNotice {
        try keys(object, allowed: [
            "type", "err_code", "error_code", "warn_code", "err_msg", "warn_msg", "message", "description", "details",
            "variant", "request_id", "status", "status_code", "retry_after", "retry_after_ms",
        ])
        if let expectedType {
            guard try string(object, "type", maximumBytes: 64) == expectedType else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
        }
        let code = try optionalString(object, "err_code", maximumBytes: 256)
            ?? optionalString(object, "error_code", maximumBytes: 256)
            ?? optionalString(object, "warn_code", maximumBytes: 256)
            ?? expectedType
            ?? "provider-error"
        let statusCode = try optionalInteger(object, "status_code") ?? optionalInteger(object, "status")
        guard statusCode.map({ 100 ... 599 ~= $0 }) ?? true else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let retryMilliseconds: Int64? = if let value = try optionalInt64(object, "retry_after_ms") {
            min(max(0, value), 3_600_000)
        } else if let seconds = try optionalDouble(object, "retry_after") {
            Int64(min(max(0, seconds * 1000), 3_600_000).rounded(.up))
        } else {
            nil
        }
        return DeepgramStreamingProviderNotice(
            code: code,
            statusCode: statusCode,
            retryAfterMilliseconds: retryMilliseconds
        )
    }

    private static func rateLimit(_ object: [String: Any]) throws -> DeepgramStreamingRateLimit {
        try keys(object, allowed: [
            "type", "scope", "limit", "remaining", "reset", "reset_at", "retry_after", "retry_after_ms", "request_id",
        ])
        let limit = try optionalInt64(object, "limit")
        let remaining = try optionalInt64(object, "remaining")
        guard limit.map({ $0 >= 0 }) ?? true,
              remaining.map({ $0 >= 0 }) ?? true
        else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        if let limit, let remaining, remaining > limit {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let reset = try optionalInt64(object, "reset_at") ?? optionalInt64(object, "reset")
        let retryMilliseconds: Int64? = if let value = try optionalInt64(object, "retry_after_ms") {
            min(max(0, value), 3_600_000)
        } else if let seconds = try optionalDouble(object, "retry_after") {
            Int64(min(max(0, seconds * 1000), 3_600_000).rounded(.up))
        } else {
            nil
        }
        return try DeepgramStreamingRateLimit(
            scope: optionalString(object, "scope", maximumBytes: 128) ?? "project-concurrency",
            limit: limit,
            remaining: remaining,
            resetsAtMilliseconds: reset,
            retryAfterMilliseconds: retryMilliseconds
        )
    }

    private static func keys(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
    }

    private static func dictionary(_ object: [String: Any], _ key: String) throws -> [String: Any] {
        guard let value = object[key] as? [String: Any] else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func dictionaryArray(
        _ object: [String: Any],
        _ key: String,
        maximumCount: Int
    ) throws -> [[String: Any]] {
        guard let values = object[key] as? [Any], values.count <= maximumCount else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return try values.map { value in
            guard let dictionary = value as? [String: Any] else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return dictionary
        }
    }

    private static func string(_ object: [String: Any], _ key: String, maximumBytes: Int) throws -> String {
        guard let value = object[key] as? String, value.utf8.count <= maximumBytes else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalString(
        _ object: [String: Any],
        _ key: String,
        maximumBytes: Int
    ) throws -> String? {
        guard let rawValue = object[key] else { return nil }
        guard let value = rawValue as? String, value.utf8.count <= maximumBytes else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalStringArray(
        _ object: [String: Any],
        _ key: String,
        maximumCount: Int
    ) throws -> [String]? {
        guard let rawValue = object[key] else { return nil }
        guard let values = rawValue as? [Any], values.count <= maximumCount else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return try values.map { value in
            guard let string = value as? String, string.utf8.count <= 32 else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return string
        }
    }

    private static func integerArray(
        _ object: [String: Any],
        _ key: String,
        maximumCount: Int
    ) throws -> [Int] {
        guard let values = object[key] as? [Any], values.count <= maximumCount else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return try values.map { value in
            guard let number = value as? NSNumber, !isBoolean(number) else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            let integer = number.intValue
            guard number.doubleValue == Double(integer) else {
                throw DeepgramMeetingTranscriptionError.protocolViolation
            }
            return integer
        }
    }

    private static func integer(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = try optionalInteger(object, key) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalInteger(_ object: [String: Any], _ key: String) throws -> Int? {
        guard let rawValue = object[key] else { return nil }
        guard let number = rawValue as? NSNumber, !isBoolean(number) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let value = number.intValue
        guard number.doubleValue == Double(value) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalInt64(_ object: [String: Any], _ key: String) throws -> Int64? {
        guard let rawValue = object[key] else { return nil }
        guard let number = rawValue as? NSNumber, !isBoolean(number) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let value = number.int64Value
        guard number.doubleValue == Double(value) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func finiteNonnegativeDouble(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = try optionalDouble(object, key), value.isFinite, value >= 0 else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalDouble(_ object: [String: Any], _ key: String) throws -> Double? {
        guard let rawValue = object[key] else { return nil }
        guard let number = rawValue as? NSNumber, !isBoolean(number) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        let value = number.doubleValue
        guard value.isFinite else { throw DeepgramMeetingTranscriptionError.protocolViolation }
        return value
    }

    private static func probability(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = try optionalProbability(object, key) else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func optionalProbability(_ object: [String: Any], _ key: String) throws -> Double? {
        guard let value = try optionalDouble(object, key) else { return nil }
        guard 0 ... 1 ~= value else { throw DeepgramMeetingTranscriptionError.protocolViolation }
        return value
    }

    private static func optionalBoolean(_ object: [String: Any], _ key: String) throws -> Bool? {
        guard let rawValue = object[key] else { return nil }
        guard let value = rawValue as? Bool else {
            throw DeepgramMeetingTranscriptionError.protocolViolation
        }
        return value
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
