import Foundation
import Testing

@testable import Kaji

@Suite("Meeting transcription validation")
struct MeetingTranscriptionValidationTests {
    @Test("conditional capabilities require explicit conditions")
    func conditionalCapabilityValidation() throws {
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try MeetingTranscriptionCapabilitySupport(.conditional)
        }
        let support = try MeetingTranscriptionCapabilitySupport(
            .conditional,
            conditions: [MeetingTranscriptionCapabilityCondition(identifier: "language", value: "en-US")]
        )
        #expect(support.availability == .conditional)
    }

    @Test("provider descriptors validate again while decoding")
    func descriptorDecodingValidation() throws {
        let descriptor = try MeetingTranscriptionCoreFixtures.descriptor()
        let data = try JSONEncoder().encode(descriptor)
        #expect(try JSONDecoder().decode(MeetingTranscriptionProviderDescriptor.self, from: data) == descriptor)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var models = try #require(object["models"] as? [[String: Any]])
        models[0]["id"] = "invalid model id"
        object["models"] = models
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try JSONDecoder().decode(MeetingTranscriptionProviderDescriptor.self, from: malformed)
        }
    }

    @Test("route rejects duplicate fallback and unsupported diarization")
    func routeValidation() throws {
        let fallback = try MeetingTranscriptionFallback(
            providerID: "fallback",
            modelID: "model",
            regionID: "local",
            mode: .localChunked
        )
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try MeetingTranscriptionCoreFixtures.route(fallbacks: [fallback, fallback])
        }
        let route = try MeetingTranscriptionCoreFixtures.route()
        let descriptor = try MeetingTranscriptionCoreFixtures.descriptor(diarization: .unsupported)
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try route.validate(against: descriptor)
        }
    }

    @Test("route privacy identity survives round trip and rejects tampering")
    func privacyIdentity() throws {
        let route = try MeetingTranscriptionCoreFixtures.route()
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(MeetingTranscriptionRoute.self, from: data)
        #expect(decoded == route)
        #expect(decoded.privacyIdentity.providerID == route.providerID)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var identity = try #require(object["privacyIdentity"] as? [String: Any])
        identity["regionID"] = "tampered"
        object["privacyIdentity"] = identity
        let tampered = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try JSONDecoder().decode(MeetingTranscriptionRoute.self, from: tampered)
        }
    }

    @Test("PCM packet enforces exact bounded bytes and stable operation ID")
    func packetValidation() throws {
        let operationID = UUID()
        let packet = try MeetingTranscriptionCoreFixtures.packet(operationID: operationID)
        #expect(packet.operationID == operationID)
        #expect(try packet.replaying().operationID == operationID)
        #expect(try packet.replaying().isReplay)
        let decoded = try JSONDecoder().decode(
            MeetingNormalizedAudioPacket.self,
            from: JSONEncoder().encode(packet)
        )
        #expect(decoded == packet)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as? [String: Any])
        var range = try #require(object["sampleRange"] as? [String: Any])
        range["endFrame"] = 20_000_000
        object["sampleRange"] = range
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try JSONDecoder().decode(MeetingNormalizedAudioPacket.self, from: malformed)
        }
        #expect(throws: MeetingTranscriptionValidationError.self) {
            try MeetingNormalizedAudioPacket(
                operationID: operationID,
                sessionID: MeetingTranscriptionCoreFixtures.sessionID,
                trackID: MeetingTranscriptionCoreFixtures.trackID,
                source: .microphone,
                sampleRange: MeetingTranscriptionCoreFixtures.sampleRange(startFrame: 0, endFrame: 10),
                encoding: .pcmSigned16LittleEndian,
                sampleRateHertz: 16_000,
                channelCount: 1,
                bytes: Data(repeating: 0, count: 19),
                providerEpoch: MeetingTranscriptionCoreFixtures.epoch()
            )
        }
    }

    @Test("endpoint policy rejects non-allowlisted and private destinations")
    func endpointPolicy() throws {
        let policy = try STTEndpointPolicy(
            httpsHosts: ["api.example.com"],
            wssHosts: ["stream.example.com"]
        )
        let allowed = try #require(URL(string: "https://api.example.com/v1/transcribe"))
        try policy.validate(allowed, trustMode: .builtIn)
        let privateEndpoint = try #require(URL(string: "https://127.0.0.1/transcribe"))
        #expect(throws: STTEndpointPolicyError.self) {
            try policy.validate(privateEndpoint, trustMode: .customSelfHosted)
        }
    }
}
