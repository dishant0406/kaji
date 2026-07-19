import Foundation

enum AssemblyAIStreamingWireMessage {
    case begin(AssemblyAIStreamingBegin)
    case turn(AssemblyAIStreamingTurn)
    case termination(AssemblyAIStreamingTermination)
    case error(AssemblyAIStreamingServerError)
    case configurationUpdate
    case speakerRevision([AssemblyAIStreamingSpeakerRevision])
    case speechStarted
}

struct AssemblyAIStreamingBegin: Decodable {
    let id: String
    let expiresAt: Int64
    let configuration: Configuration?

    struct Configuration: Decodable {
        let model: String?
        let mode: String?
        let apiVersion: String?
        let speakerLabels: Bool?

        private enum CodingKeys: String, CodingKey {
            case model
            case mode
            case apiVersion = "api_version"
            case speakerLabels = "speaker_labels"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case expiresAt = "expires_at"
        case configuration
    }
}

struct AssemblyAIStreamingTurn: Decodable {
    let turnOrder: Int
    let turnIsFormatted: Bool
    let endOfTurn: Bool
    let transcript: String
    let languageCode: String?
    let languageConfidence: Double?
    let speakerLabel: String?
    let endOfTurnConfidence: Double
    let words: [AssemblyAIStreamingWord]

    private enum CodingKeys: String, CodingKey {
        case turnOrder = "turn_order"
        case turnIsFormatted = "turn_is_formatted"
        case endOfTurn = "end_of_turn"
        case transcript
        case languageCode = "language_code"
        case languageConfidence = "language_confidence"
        case speakerLabel = "speaker_label"
        case endOfTurnConfidence = "end_of_turn_confidence"
        case words
    }
}

struct AssemblyAIStreamingWord: Decodable {
    let text: String
    let start: Int64
    let end: Int64
    let confidence: Double
    let wordIsFinal: Bool
    let speaker: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case start
        case end
        case confidence
        case wordIsFinal = "word_is_final"
        case speaker
    }
}

struct AssemblyAIStreamingTermination: Decodable {
    let audioDurationSeconds: Int64
    let sessionDurationSeconds: Int64

    private enum CodingKeys: String, CodingKey {
        case audioDurationSeconds = "audio_duration_seconds"
        case sessionDurationSeconds = "session_duration_seconds"
    }
}

struct AssemblyAIStreamingServerError: Decodable {
    let errorCode: Int

    private enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
    }
}

struct AssemblyAIStreamingSpeakerRevision: Decodable {
    let turnOrder: Int
    let speakerLabel: String?
    let words: [Word]

    struct Word: Decodable {
        let text: String
        let speaker: String
        let start: Int64
        let end: Int64
    }

    private enum CodingKeys: String, CodingKey {
        case turnOrder = "turn_order"
        case speakerLabel = "speaker_label"
        case words
    }
}

enum AssemblyAIStreamingWireDecoder {
    static func decode(_ text: String, maximumBytes: Int) throws -> AssemblyAIStreamingWireMessage {
        let data = Data(text.utf8)
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw data.count > maximumBytes ? AssemblyAIMeetingTranscriptionError.responseTooLarge :
                AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any], let type = object["type"] as? String else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        let decoder = JSONDecoder()
        switch type {
        case "Begin":
            try validateKeys(object, allowed: ["type", "id", "expires_at", "configuration"])
            if let configuration = object["configuration"] as? [String: Any] {
                try validateKeys(
                    configuration,
                    allowed: ["model", "mode", "api_version", "speaker_labels", "redact_pii", "filter_profanity", "domain", "voice_focus"]
                )
            }
            return try .begin(decoder.decode(AssemblyAIStreamingBegin.self, from: data))
        case "Turn":
            try validateKeys(
                object,
                allowed: [
                    "type", "turn_order", "turn_is_formatted", "end_of_turn", "transcript", "utterance", "language_code",
                    "language_confidence", "speaker_label", "end_of_turn_confidence", "words",
                ]
            )
            try validateArrayKeys(
                object["words"],
                allowed: ["text", "start", "end", "confidence", "word_is_final", "speaker"],
                maximumCount: 10000
            )
            return try .turn(decoder.decode(AssemblyAIStreamingTurn.self, from: data))
        case "Termination":
            try validateKeys(object, allowed: ["type", "audio_duration_seconds", "session_duration_seconds"])
            return try .termination(decoder.decode(AssemblyAIStreamingTermination.self, from: data))
        case "Error":
            try validateKeys(object, allowed: ["type", "error_code", "error"])
            guard let error = object["error"] as? String, error.utf8.count <= 2000 else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
            return try .error(decoder.decode(AssemblyAIStreamingServerError.self, from: data))
        case "SpeakerRevision":
            try validateKeys(object, allowed: ["type", "revisions"])
            try validateArrayKeys(
                object["revisions"],
                allowed: ["turn_order", "speaker_label", "words"],
                maximumCount: 10000
            )
            guard let revisions = object["revisions"] as? [[String: Any]] else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
            for revision in revisions {
                try validateArrayKeys(
                    revision["words"],
                    allowed: ["text", "speaker", "start", "end"],
                    maximumCount: 10000
                )
                guard revision.keys.contains("speaker_label") else {
                    throw AssemblyAIMeetingTranscriptionError.malformedResponse
                }
            }
            struct Envelope: Decodable { let revisions: [AssemblyAIStreamingSpeakerRevision] }
            return try .speakerRevision(decoder.decode(Envelope.self, from: data).revisions)
        case "SpeechStarted":
            try validateKeys(object, allowed: ["type", "timestamp", "confidence"])
            guard let timestamp = object["timestamp"] as? NSNumber,
                  let confidence = object["confidence"] as? NSNumber,
                  !(object["timestamp"] is Bool),
                  !(object["confidence"] is Bool),
                  timestamp.int64Value >= 0,
                  confidence.doubleValue.isFinite,
                  0 ... 1 ~= confidence.doubleValue
            else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
            return .speechStarted
        case "UpdateConfiguration",
             "Configuration":
            try validateKeys(
                object,
                allowed: [
                    "type", "prompt", "keyterms_prompt", "language_codes", "mode", "min_turn_silence", "max_turn_silence",
                    "end_of_turn_confidence_threshold", "continuous_partials", "vad_threshold", "interruption_delay", "agent_context",
                ]
            )
            try validateConfigurationUpdate(object)
            return .configurationUpdate
        default:
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }

    private static func validateKeys(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }

    private static func validateArrayKeys(_ value: Any?, allowed: Set<String>, maximumCount: Int) throws {
        guard let objects = value as? [[String: Any]], objects.count <= maximumCount else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
        for object in objects {
            try validateKeys(object, allowed: allowed)
        }
    }

    private static func validateConfigurationUpdate(_ object: [String: Any]) throws {
        if let prompt = object["prompt"] {
            guard let prompt = prompt as? String, !prompt.isEmpty, prompt.count <= 1750 else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
        }
        if let agentContext = object["agent_context"] {
            guard let agentContext = agentContext as? String, !agentContext.isEmpty, agentContext.count <= 1750 else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
        }
        try validateStringArray(object["keyterms_prompt"], maximumCount: 100, allowEmpty: false)
        try validateStringArray(object["language_codes"], maximumCount: 18, allowEmpty: true)
        if let mode = object["mode"] {
            guard let mode = mode as? String, ["max_accuracy", "min_latency", "balanced"].contains(mode) else {
                throw AssemblyAIMeetingTranscriptionError.malformedResponse
            }
        }
        try validateInteger(object["min_turn_silence"], range: 50 ... 10000)
        try validateInteger(object["max_turn_silence"], range: 50 ... 10000)
        try validateInteger(object["interruption_delay"], range: 0 ... 1000)
        try validateUnitInterval(object["end_of_turn_confidence_threshold"])
        try validateUnitInterval(object["vad_threshold"])
        if let continuousPartials = object["continuous_partials"], !(continuousPartials is Bool) {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }

    private static func validateStringArray(_ value: Any?, maximumCount: Int, allowEmpty: Bool) throws {
        guard let value else { return }
        guard let values = value as? [String],
              values.count <= maximumCount,
              allowEmpty || !values.isEmpty,
              Set(values).count == values.count,
              values.allSatisfy({ !$0.isEmpty && $0.count <= 200 })
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }

    private static func validateInteger(_ value: Any?, range: ClosedRange<Int>) throws {
        guard let value else { return }
        guard let number = value as? NSNumber,
              !(value is Bool),
              number.doubleValue == Double(number.intValue),
              range.contains(number.intValue)
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }

    private static func validateUnitInterval(_ value: Any?) throws {
        guard let value else { return }
        guard let number = value as? NSNumber,
              !(value is Bool),
              number.doubleValue.isFinite,
              0 ... 1 ~= number.doubleValue
        else {
            throw AssemblyAIMeetingTranscriptionError.malformedResponse
        }
    }
}
