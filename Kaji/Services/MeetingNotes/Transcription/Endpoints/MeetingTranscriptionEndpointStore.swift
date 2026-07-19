import Foundation
import Observation

@MainActor
@Observable
final class MeetingTranscriptionEndpointStore {
    static let shared = MeetingTranscriptionEndpointStore()
    static let maximumFileBytes = 256 * 1024

    private(set) var profiles: [MeetingTranscriptionEndpointProfile] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let bundledLoader: @MainActor () throws -> MeetingTranscriptionEndpointRegistryDocument

    convenience init(fileURL: URL = KajiFileStorage.fileURL(filename: "meeting-stt-endpoints.json")) {
        self.init(fileURL: fileURL, bundledLoader: MeetingTranscriptionEndpointStore.loadBundled)
    }

    init(
        fileURL: URL,
        bundledLoader: @escaping @MainActor () throws -> MeetingTranscriptionEndpointRegistryDocument
    ) {
        self.fileURL = fileURL
        self.bundledLoader = bundledLoader
        reload()
    }

    func profiles(providerID: String) -> [MeetingTranscriptionEndpointProfile] {
        profiles.filter { $0.providerID == providerID }.sorted { left, right in
            if left.source != right.source { return left.source == .builtIn }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    func profile(id: UUID?) -> MeetingTranscriptionEndpointProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func defaultProfile(providerID: String, regionID: String? = nil) -> MeetingTranscriptionEndpointProfile? {
        let matches = profiles(providerID: providerID)
        if let regionID, let exact = matches.first(where: { $0.regionID == regionID }) { return exact }
        return matches.first
    }

    func saveCustom(_ profile: MeetingTranscriptionEndpointProfile) throws {
        guard profile.source == .custom else { throw MeetingTranscriptionEndpointProfileError.invalidProfile }
        try validateCustomOrigins(profile)
        let builtIns = profiles.filter { $0.source == .builtIn }
        var custom = profiles.filter { $0.source == .custom && $0.id != profile.id }
        guard !builtIns.contains(where: { $0.id == profile.id }),
              !custom.contains(where: { $0.providerID == profile.providerID && $0.regionID == profile.regionID })
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        custom.append(profile)
        try persist(custom)
        profiles = Self.sorted(builtIns + custom)
        errorMessage = nil
    }

    func deleteCustom(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id && $0.source == .custom }) else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        let builtIns = profiles.filter { $0.source == .builtIn }
        let custom = profiles.filter { $0.source == .custom && $0.id != id }
        try persist(custom)
        profiles = Self.sorted(builtIns + custom)
        errorMessage = nil
    }

    func reload() {
        do {
            let builtIns = try bundledLoader().profiles
            let custom = try loadCustomProfiles()
            let combined = builtIns + custom
            guard Set(combined.map(\.id)).count == combined.count,
                  Set(combined.map { "\($0.providerID)|\($0.regionID)" }).count == combined.count
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidProfile
            }
            try custom.forEach(validateCustomOrigins)
            profiles = Self.sorted(combined)
            errorMessage = nil
        } catch {
            profiles = (try? bundledLoader().profiles).map(Self.sorted) ?? []
            errorMessage = "Custom transcription endpoints could not be loaded."
        }
    }

    private func loadCustomProfiles() throws -> [MeetingTranscriptionEndpointProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumFileBytes
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let document = try JSONDecoder().decode(MeetingTranscriptionEndpointRegistryDocument.self, from: data)
        guard document.profiles.allSatisfy({ $0.source == .custom }) else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        return document.profiles
    }

    private func persist(_ custom: [MeetingTranscriptionEndpointProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try Self.ensureSecureDirectory(directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw MeetingTranscriptionEndpointProfileError.invalidProfile
            }
        }
        let document = try MeetingTranscriptionEndpointRegistryDocument(profiles: custom)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumFileBytes else {
            throw MeetingTranscriptionEndpointProfileError.invalidProfile
        }
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validateCustomOrigins(_ profile: MeetingTranscriptionEndpointProfile) throws {
        for text in [profile.restBaseURL, profile.webSocketBaseURL].compactMap(\.self) {
            guard let url = URL(string: text), let host = url.host?.lowercased(), STTEndpointPolicy.isSafeCustomHost(host) else {
                throw MeetingTranscriptionEndpointProfileError.invalidURL
            }
        }
    }

    private static func ensureSecureDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingTranscriptionEndpointProfileError.invalidProfile
            }
        } else {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func sorted(_ profiles: [MeetingTranscriptionEndpointProfile]) -> [MeetingTranscriptionEndpointProfile] {
        profiles.sorted { left, right in
            if left.providerID != right.providerID { return left.providerID < right.providerID }
            if left.source != right.source { return left.source == .builtIn }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    private static func loadBundled() throws -> MeetingTranscriptionEndpointRegistryDocument {
        let url = Bundle.appResources.url(forResource: "meeting-transcription-endpoints", withExtension: "json")
            ?? Bundle.main.url(forResource: "meeting-transcription-endpoints", withExtension: "json")
        guard let url else { throw MeetingTranscriptionEndpointProfileError.endpointUnavailable }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumFileBytes else { throw MeetingTranscriptionEndpointProfileError.invalidProfile }
        return try JSONDecoder().decode(MeetingTranscriptionEndpointRegistryDocument.self, from: data)
    }
}
