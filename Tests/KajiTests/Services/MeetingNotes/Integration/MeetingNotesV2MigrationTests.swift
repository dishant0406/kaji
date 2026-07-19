import Foundation
import Testing

@testable import Kaji

@Suite("Meeting notes v2 migration")
struct MeetingNotesV2MigrationTests {
    @Test("v1 settings migrate notes keys and default to local FluidAudio")
    func settingsMigration() throws {
        let data = Data("""
        {
          "synthesisIntervalMinutes": 4,
          "includeSystemAudio": true,
          "includeMicrophone": false,
          "retentionDays": 14,
          "shareProjectContext": false,
          "contextScope": "active",
          "providerID": "notes-provider",
          "modelID": "notes-model",
          "styleInstructions": "Concise"
        }
        """.utf8)

        let settings = try JSONDecoder().decode(MeetingNotesIntegrationSettings.self, from: data)

        #expect(settings.version == MeetingNotesIntegrationSettings.currentVersion)
        #expect(settings.notesProviderID == "notes-provider")
        #expect(settings.notesModelID == "notes-model")
        #expect(settings.sttProviderID == FluidAudioMeetingTranscriptionProvider.providerID)
        #expect(settings.sttModelID.isEmpty)
        #expect(settings.sttMode == .localChunked)
        #expect(settings.sttCredentialProfileID == nil)
        #expect(!settings.localFallbackEnabled)
        let encoded = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["version"] as? Int == MeetingNotesIntegrationSettings.currentVersion)
        #expect(object["notesProviderID"] as? String == "notes-provider")
        #expect(object["providerID"] == nil)
    }

    @Test("v1 session configuration migrates to an exact local route")
    func sessionConfigurationMigration() throws {
        let data = Data("""
        {
          "synthesisIntervalMinutes": 5,
          "includeSystemAudio": true,
          "includeMicrophone": true,
          "retainRawAudio": false,
          "retentionDays": 30,
          "shareProjectContext": false,
          "contextScope": "active",
          "providerID": "notes-provider",
          "modelID": "notes-model",
          "styleInstructions": "",
          "disclosureVersion": 1,
          "consentedAtMilliseconds": 1000
        }
        """.utf8)

        let configuration = try JSONDecoder().decode(MeetingSessionConfiguration.self, from: data)

        #expect(configuration.version == MeetingSessionConfiguration.currentVersion)
        #expect(configuration.notesProviderID == "notes-provider")
        #expect(configuration.transcriptionRoute.providerID == FluidAudioMeetingTranscriptionProvider.providerID)
        #expect(configuration.transcriptionRoute.mode == .localChunked)
        #expect(configuration.rawAudioRecipient == "this-mac")
        #expect(configuration.sttAccountAttestations.isEmpty)
        #expect(configuration.disclosureClaims.isEmpty)
        #expect(configuration.consentExpiresAtMilliseconds == configuration.consentedAtMilliseconds)
    }

    @Test("v1 session document decodes as v2 and validates")
    func documentMigration() throws {
        let document = try MeetingNotesTestFixtures.document()
        let encoded = try JSONEncoder().encode(document)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 1
        object["configuration"] = [
            "synthesisIntervalMinutes": 5,
            "includeSystemAudio": false,
            "includeMicrophone": false,
            "retainRawAudio": false,
            "retentionDays": 30,
            "shareProjectContext": false,
            "contextScope": "active",
            "providerID": "",
            "modelID": "",
            "styleInstructions": "",
            "disclosureVersion": 0,
            "consentedAtMilliseconds": 0,
        ]
        let migratedData = try JSONSerialization.data(withJSONObject: object)

        let migrated = try JSONDecoder().decode(MeetingSessionDocument.self, from: migratedData)

        #expect(migrated.version == MeetingSessionDocument.currentVersion)
        #expect(migrated.committedTranscriptMetadata.isEmpty)
        #expect(migrated.transcriptionGaps.isEmpty)
        try MeetingDocumentValidator().validate(migrated)
    }

    @Test("v2 pending synthesis cursor migrates to retry state")
    func synthesisCursorMigration() throws {
        let segment = try MeetingNotesTestFixtures.segment()
        let document = MeetingSessionDocument(
            session: try MeetingNotesTestFixtures.session(phase: .completed),
            tracks: [MeetingNotesTestFixtures.track()],
            transcriptSegments: [segment]
        )
        let encoded = try JSONEncoder().encode(document)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 2
        object["synthesisState"] = [
            "synthesizedSegmentIDs": [],
            "pendingSegmentIDs": [segment.id.uuidString],
            "isPending": true,
        ]

        let migrated = try JSONDecoder().decode(
            MeetingSessionDocument.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(migrated.version == MeetingSessionDocument.currentVersion)
        #expect(migrated.synthesisState.status == .retryScheduled)
        #expect(migrated.synthesisState.pendingSegmentIDs == [segment.id])
        #expect(migrated.synthesisState.attemptCount == 0)
        #expect(migrated.synthesisState.lastErrorCode == nil)
        try MeetingDocumentValidator().validate(migrated)
    }
}
