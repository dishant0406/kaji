import Foundation

enum MeetingNotesSettingsError: Error, Equatable {
    case invalidSynthesisInterval
    case invalidRetentionDays
}

struct MeetingNotesSettings: Codable, Equatable {
    static let privacyDefaults = Self(
        validatedSynthesisIntervalMinutes: 5,
        retainRawAudio: false,
        retentionDays: 30,
        includeSystemAudio: false,
        shareProjectContext: false
    )

    let synthesisIntervalMinutes: Int
    let retainRawAudio: Bool
    let retentionDays: Int
    let includeSystemAudio: Bool
    let shareProjectContext: Bool

    init(
        synthesisIntervalMinutes: Int,
        retainRawAudio: Bool = false,
        retentionDays: Int = 30,
        includeSystemAudio: Bool = false,
        shareProjectContext: Bool = false
    ) throws {
        guard (1 ... 30).contains(synthesisIntervalMinutes) else {
            throw MeetingNotesSettingsError.invalidSynthesisInterval
        }
        guard (1 ... 3650).contains(retentionDays) else {
            throw MeetingNotesSettingsError.invalidRetentionDays
        }
        self.init(
            validatedSynthesisIntervalMinutes: synthesisIntervalMinutes,
            retainRawAudio: retainRawAudio,
            retentionDays: retentionDays,
            includeSystemAudio: includeSystemAudio,
            shareProjectContext: shareProjectContext
        )
    }

    private init(
        validatedSynthesisIntervalMinutes: Int,
        retainRawAudio: Bool,
        retentionDays: Int,
        includeSystemAudio: Bool,
        shareProjectContext: Bool
    ) {
        synthesisIntervalMinutes = validatedSynthesisIntervalMinutes
        self.retainRawAudio = retainRawAudio
        self.retentionDays = retentionDays
        self.includeSystemAudio = includeSystemAudio
        self.shareProjectContext = shareProjectContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            synthesisIntervalMinutes: container.decode(Int.self, forKey: .synthesisIntervalMinutes),
            retainRawAudio: container.decode(Bool.self, forKey: .retainRawAudio),
            retentionDays: container.decode(Int.self, forKey: .retentionDays),
            includeSystemAudio: container.decode(Bool.self, forKey: .includeSystemAudio),
            shareProjectContext: container.decode(Bool.self, forKey: .shareProjectContext)
        )
    }
}
