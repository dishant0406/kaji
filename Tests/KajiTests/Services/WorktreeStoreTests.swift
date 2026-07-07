import Foundation
import Testing

@testable import Kaji

@Suite("WorktreeStore")
@MainActor
struct WorktreeStoreTests {
    @Test("records without backend decode as Rift workspaces")
    func worktreeDecodeDefaultsToRift() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "feature-a",
          "path": "/tmp/feature-a",
          "branch": "feature-a",
          "isPrimary": false,
          "createdAt": "2024-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let worktree = try decoder.decode(Worktree.self, from: Data(json.utf8))

        #expect(worktree.source == .kaji)
        #expect(worktree.backend == .rift)
        #expect(!worktree.isExternallyManaged)
    }

    @Test("new records default to primary or Rift backend")
    func newRecordsDefaultToRiftBackends() {
        let primary = Worktree(name: "Primary", path: "/tmp/repo", isPrimary: true)
        let managed = Worktree(name: "Managed", path: "/tmp/managed", isPrimary: false)

        #expect(primary.backend == .primary)
        #expect(managed.backend == .rift)
        #expect(managed.canBeRemoved)
    }

    @Test("external workspaces cannot be removed from Kaji")
    func externalWorkspacesCannotBeRemoved() {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let external = Worktree(
            name: "feature-b",
            path: "/tmp/repo-feature-b",
            source: .external,
            backend: .externalRift,
            isPrimary: false
        )
        let store = WorktreeStore(
            persistence: WorktreePersistenceStub(initial: [
                project.id: [Worktree(name: project.name, path: project.path, isPrimary: true), external],
            ]),
            listRiftWorkspaces: RiftWorkspaceListingStub(recordsByRepoPath: [:]).listWorkspaces,
            projects: [project]
        )

        store.remove(worktreeID: external.id, from: project.id)

        #expect(store.list(for: project.id).contains(external))
        #expect(!external.canBeRemoved)
    }

    @Test("refreshFromRift imports missing external workspaces and preserves IDs")
    func refreshFromRiftImportsAndPreservesIDs() async throws {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let existingID = UUID()
        let createdAt = Date(timeIntervalSince1970: 123)
        let store = WorktreeStore(
            persistence: WorktreePersistenceStub(initial: [
                project.id: [
                    Worktree(name: project.name, path: project.path, isPrimary: true),
                    Worktree(
                        id: existingID,
                        name: "Feature A",
                        path: "/tmp/repo-feature-a",
                        branch: "feature-a",
                        source: .kaji,
                        backend: .rift,
                        riftID: "old",
                        isPrimary: false,
                        createdAt: createdAt
                    ),
                ],
            ]),
            listRiftWorkspaces: RiftWorkspaceListingStub(recordsByRepoPath: [
                project.path: [
                    RiftWorkspaceRecord(path: "/tmp/repo-feature-a", riftID: "rift-a"),
                    RiftWorkspaceRecord(path: "/tmp/repo-feature-b", riftID: "rift-b"),
                ],
            ]).listWorkspaces,
            projects: [project]
        )

        let worktrees = try await store.refreshFromRift(project: project)

        let preserved = try #require(worktrees.first { $0.path == "/tmp/repo-feature-a" })
        #expect(preserved.id == existingID)
        #expect(preserved.branch == "feature-a")
        #expect(preserved.backend == .rift)
        #expect(preserved.riftID == "rift-a")
        #expect(preserved.createdAt == createdAt)

        let imported = try #require(worktrees.first { $0.path == "/tmp/repo-feature-b" })
        #expect(imported.name == "repo-feature-b")
        #expect(imported.source == .external)
        #expect(imported.backend == .externalRift)
        #expect(imported.riftID == "rift-b")
    }

    @Test("refreshFromRift keeps missing Kaji-managed records and removes missing external records")
    func refreshFromRiftRetentionPolicy() async throws {
        let project = Project(name: "Repo", path: "/tmp/repo")
        let managed = Worktree(name: "Retained", path: "/tmp/repo-retained", backend: .rift, isPrimary: false)
        let external = Worktree(
            name: "External",
            path: "/tmp/repo-external",
            source: .external,
            backend: .externalRift,
            isPrimary: false
        )
        let store = WorktreeStore(
            persistence: WorktreePersistenceStub(initial: [
                project.id: [Worktree(name: project.name, path: project.path, isPrimary: true), managed, external],
            ]),
            listRiftWorkspaces: RiftWorkspaceListingStub(recordsByRepoPath: [project.path: []]).listWorkspaces,
            projects: [project]
        )

        let worktrees = try await store.refreshFromRift(project: project)

        #expect(worktrees.contains(where: { $0.id == managed.id }))
        #expect(!worktrees.contains(where: { $0.id == external.id }))
    }

    @Test("refreshFromRift treats symlinked primary path as primary workspace")
    func refreshFromRiftResolvesSymlinkedPrimaryPath() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kaji-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let realRepo = tempRoot.appendingPathComponent("real-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: realRepo, withIntermediateDirectories: true)
        let symlink = tempRoot.appendingPathComponent("linked-repo")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realRepo)
        let project = Project(name: "Repo", path: symlink.path)
        let store = WorktreeStore(
            persistence: WorktreePersistenceStub(initial: [
                project.id: [Worktree(name: project.name, path: symlink.path, isPrimary: true)],
            ]),
            listRiftWorkspaces: RiftWorkspaceListingStub(recordsByRepoPath: [
                project.path: [RiftWorkspaceRecord(path: realRepo.path, riftID: "root")],
            ]).listWorkspaces,
            projects: [project]
        )

        let worktrees = try await store.refreshFromRift(project: project)

        #expect(worktrees.count == 1)
        #expect(worktrees[0].isPrimary)
    }
}

private final class WorktreePersistenceStub: WorktreePersisting {
    private var storage: [UUID: [Worktree]]

    init(initial: [UUID: [Worktree]]) {
        storage = initial
    }

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        storage[projectID] ?? []
    }

    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws {
        storage[projectID] = worktrees
    }

    func removeWorktrees(projectID: UUID) throws {
        storage.removeValue(forKey: projectID)
    }
}

private struct RiftWorkspaceListingStub {
    let recordsByRepoPath: [String: [RiftWorkspaceRecord]]

    func listWorkspaces(repoPath: String) async throws -> [RiftWorkspaceRecord] {
        recordsByRepoPath[repoPath] ?? []
    }
}
