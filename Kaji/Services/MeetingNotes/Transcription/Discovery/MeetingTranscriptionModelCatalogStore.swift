import Foundation
import Observation

private struct MeetingTranscriptionModelCatalogDocument: Codable {
    static let currentVersion = 1

    let version: Int
    let catalogs: [MeetingTranscriptionModelCatalogSnapshot]

    init(catalogs: [MeetingTranscriptionModelCatalogSnapshot]) throws {
        guard catalogs.count <= 128, Set(catalogs.map(\.id)).count == catalogs.count else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        version = Self.currentVersion
        self.catalogs = catalogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let catalogs = try container.decode([MeetingTranscriptionModelCatalogSnapshot].self, forKey: .catalogs)
        guard version == Self.currentVersion,
              catalogs.count <= 128,
              Set(catalogs.map(\.id)).count == catalogs.count
        else {
            throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
        }
        self.version = version
        self.catalogs = catalogs
    }
}

@MainActor
@Observable
final class MeetingTranscriptionModelCatalogStore {
    static let shared = MeetingTranscriptionModelCatalogStore(
        discoverer: try? RemoteMeetingTranscriptionModelDiscovery()
    )
    static let maximumFileBytes = 2 * 1024 * 1024

    private(set) var states: [String: MeetingTranscriptionModelDiscoveryState] = [:]
    private(set) var catalogs: [String: MeetingTranscriptionModelCatalogSnapshot] = [:]

    @ObservationIgnored private let discoverer: (any MeetingTranscriptionModelDiscovering)?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var refreshTasks: [String: Task<Void, Never>] = [:]

    init(
        discoverer: (any MeetingTranscriptionModelDiscovering)?,
        fileURL: URL = KajiFileStorage.fileURL(filename: "meeting-stt-model-catalogs.json")
    ) {
        self.discoverer = discoverer
        self.fileURL = fileURL
        load()
    }

    deinit {
        for task in refreshTasks.values {
            task.cancel()
        }
    }

    func catalog(endpointProfileID: UUID, credentialProfileID: UUID?) -> MeetingTranscriptionModelCatalogSnapshot? {
        catalogs[Self.key(endpointProfileID: endpointProfileID, credentialProfileID: credentialProfileID)]
    }

    func state(endpointProfileID: UUID, credentialProfileID: UUID?) -> MeetingTranscriptionModelDiscoveryState {
        states[Self.key(endpointProfileID: endpointProfileID, credentialProfileID: credentialProfileID)] ?? .idle
    }

    func refresh(
        endpoint: MeetingTranscriptionEndpointSnapshot,
        credentialProfileID: UUID?,
        credentialStore: any STTCredentialProfileStoring,
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            max(0, Int64(Date().timeIntervalSince1970 * 1000))
        }
    ) {
        let key = Self.key(endpointProfileID: endpoint.profileID, credentialProfileID: credentialProfileID)
        refreshTasks[key]?.cancel()
        states[key] = .loading
        guard let discoverer else {
            states[key] = .failed("Model discovery is unavailable.")
            return
        }
        refreshTasks[key] = Task { [weak self] in
            do {
                let models = try await discoverer.discover(
                    endpoint: endpoint,
                    credentialProfileID: credentialProfileID,
                    credentialStore: credentialStore
                )
                try Task.checkCancellation()
                let snapshot = try MeetingTranscriptionModelCatalogSnapshot(
                    endpointProfileID: endpoint.profileID,
                    credentialProfileID: credentialProfileID,
                    endpointFingerprint: endpoint.originFingerprint,
                    fetchedAtMilliseconds: nowMilliseconds(),
                    models: models
                )
                guard let self else { return }
                catalogs[key] = snapshot
                states[key] = .loaded
                persist()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                states[key] = catalogs[key] == nil
                    ? .failed("Models could not be loaded from this endpoint.")
                    : .stale("The last successful model list is being shown.")
            }
        }
    }

    func remove(endpointProfileID: UUID) {
        let keys = catalogs.keys.filter { catalogs[$0]?.endpointProfileID == endpointProfileID }
        for key in keys {
            catalogs.removeValue(forKey: key)
            states.removeValue(forKey: key)
            refreshTasks.removeValue(forKey: key)?.cancel()
        }
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumFileBytes
            else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let document = try JSONDecoder().decode(MeetingTranscriptionModelCatalogDocument.self, from: data)
            catalogs = Dictionary(uniqueKeysWithValues: document.catalogs.map { ($0.id, $0) })
            states = Dictionary(uniqueKeysWithValues: document.catalogs.map { ($0.id, .loaded) })
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            catalogs = [:]
            states = [:]
        }
    }

    private func persist() {
        do {
            let document = try MeetingTranscriptionModelCatalogDocument(catalogs: Array(catalogs.values))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            guard data.count <= Self.maximumFileBytes else {
                throw MeetingTranscriptionEndpointProfileError.invalidDiscovery
            }
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingTranscriptionEndpointProfileError.invalidProfile
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw MeetingTranscriptionEndpointProfileError.invalidProfile
                }
            }
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            return
        }
    }

    private static func key(endpointProfileID: UUID, credentialProfileID: UUID?) -> String {
        "\(endpointProfileID.uuidString.lowercased())|\(credentialProfileID?.uuidString.lowercased() ?? "none")"
    }
}
