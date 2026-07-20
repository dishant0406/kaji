import Foundation
import Testing

@testable import Kaji

@Suite("WorkspaceSnapshot")
@MainActor
struct WorkspaceSnapshotTests {
    private let testPath = "/tmp/test"

    @Test("TerminalTabSnapshot Codable round-trip for editor")
    func terminalTabSnapshotRoundTrip() throws {
        let snapshot = TerminalTabSnapshot(
            kind: .editor,
            customTitle: "Editor",
            colorID: "blue",
            isPinned: true,
            projectPath: testPath,
            paneTitle: "main.swift",
            filePath: "/tmp/test/main.swift"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)

        #expect(decoded.kind == .editor)
        #expect(decoded.customTitle == "Editor")
        #expect(decoded.colorID == "blue")
        #expect(decoded.isPinned)
        #expect(decoded.filePath == "/tmp/test/main.swift")
    }

    @Test("TerminalTabSnapshot Codable round-trip for file preview")
    func filePreviewSnapshotRoundTrip() throws {
        let snapshot = TerminalTabSnapshot(
            kind: .filePreview,
            customTitle: nil,
            colorID: nil,
            isPinned: false,
            projectPath: testPath,
            paneTitle: "Preview",
            filePath: "/tmp/test/image.png"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)

        #expect(decoded.kind == .filePreview)
        #expect(decoded.filePath == "/tmp/test/image.png")
    }

    @Test("WorkspaceSnapshot Codable round-trip for workspace tabs")
    func workspaceSnapshotRoundTrip() throws {
        let areaID = UUID()
        let workspaceTab = WorkspaceTabSnapshot(
            id: UUID(),
            customTitle: "Shell",
            colorID: "blue",
            isPinned: true,
            focusedAreaID: areaID,
            root: .tabArea(TabAreaSnapshot(
                id: areaID,
                projectPath: testPath,
                tabs: [TerminalTabSnapshot(
                    kind: .terminal,
                    customTitle: nil,
                    colorID: nil,
                    isPinned: false,
                    projectPath: testPath,
                    paneTitle: "Shell"
                )],
                activeTabIndex: 0
            ))
        )
        let snapshot = WorkspaceSnapshot(
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: testPath,
            tabs: [workspaceTab],
            activeTabID: workspaceTab.id
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)

        #expect(decoded.tabs.count == 1)
        #expect(decoded.activeTabID == workspaceTab.id)
    }

    @Test("TerminalTabSnapshot Codable round-trip for browser pages")
    func browserSnapshotRoundTrip() throws {
        let firstID = UUID()
        let secondID = UUID()
        let snapshot = TerminalTabSnapshot(
            kind: .browser,
            customTitle: nil,
            colorID: nil,
            isPinned: false,
            projectPath: testPath,
            paneTitle: "Browser",
            browserURL: "https://one.example",
            browserPages: [
                BrowserPageSnapshot(id: firstID, url: "https://one.example", title: "One"),
                BrowserPageSnapshot(id: secondID, url: "https://two.example", title: "Two"),
            ],
            selectedBrowserPageID: secondID,
            browserDeviceProfileID: "iphone-15-pro"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)

        #expect(decoded.browserPages?.count == 2)
        #expect(decoded.browserPages?.last?.url == "https://two.example")
        #expect(decoded.selectedBrowserPageID == secondID)
        #expect(decoded.browserDeviceProfileID == "iphone-15-pro")
    }

    @Test("TerminalTabSnapshot Codable round-trip for parent agent identity")
    func parentAgentSnapshotRoundTrip() throws {
        let agentID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let snapshot = TerminalTabSnapshot(
            kind: .parentAgent,
            customTitle: nil,
            colorID: nil,
            isPinned: false,
            projectPath: testPath,
            paneTitle: "Kaji",
            parentAgentID: agentID,
            parentAgentProjectID: projectID,
            parentAgentWorktreeID: worktreeID,
            parentAgentInitialSessionPath: "/tmp/session.jsonl"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)

        #expect(decoded.kind == .parentAgent)
        #expect(decoded.parentAgentID == agentID)
        #expect(decoded.parentAgentProjectID == projectID)
        #expect(decoded.parentAgentWorktreeID == worktreeID)
        #expect(decoded.parentAgentInitialSessionPath == "/tmp/session.jsonl")
    }

    @Test("legacy root snapshot upgrades hidden pane tabs into workspace tabs")
    func legacySnapshotUpgrade() throws {
        let areaID = UUID()
        let json = """
        {
          "projectID":"\(UUID().uuidString)",
          "worktreeID":"\(UUID().uuidString)",
          "worktreePath":"\(testPath)",
          "focusedAreaID":"\(areaID.uuidString)",
          "root":{
            "type":"tabArea",
            "tabArea":{
              "id":"\(areaID.uuidString)",
              "projectPath":"\(testPath)",
              "tabs":[
                {"kind":"terminal","customTitle":"One","isPinned":false,"projectPath":"\(testPath)","paneTitle":"One"},
                {"kind":"terminal","customTitle":"Two","isPinned":false,"projectPath":"\(testPath)","paneTitle":"Two"}
              ],
              "activeTabIndex":0
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))
        #expect(decoded.tabs.count == 2)
    }

    @Test("WorkspaceRestorer snapshotAll and restoreAll preserve workspaces")
    func snapshotAndRestore() {
        let project = Project(name: "Test", path: testPath)
        let worktree = Worktree(name: "main", path: testPath, isPrimary: true)
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let area = TabArea(projectPath: testPath)
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)

        let snapshots = WorkspaceRestorer.snapshotAll(workspaces: [key: workspace])
        let restored = WorkspaceRestorer.restoreAll(
            from: snapshots,
            projects: [project],
            worktrees: [project.id: [worktree]]
        )

        #expect(snapshots.count == 1)
        #expect(restored.count == 1)
        #expect(restored[0].workspace.tabs.count == 1)
        #expect(restored[0].workspace.activeTab?.focusedAreaID == area.id)
    }

    @Test("WorkspaceRestorer restores legacy parent agent tabs as KajiCode commands")
    func parentAgentTabsRestoreAsKajiCodeCommands() throws {
        let project = Project(name: "Test", path: testPath)
        let worktree = Worktree(name: "main", path: testPath, isPrimary: true)
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let agentID = UUID()
        let agent = TerminalTab(parentAgentState: ParentAgentTabState(
            id: agentID,
            projectID: project.id,
            worktreeID: worktree.id,
            projectPath: testPath,
            initialSessionPath: "/tmp/session.jsonl"
        ))
        let area = TabArea(projectPath: testPath, existingTab: agent)
        let tab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [tab], activeTabID: tab.id)

        let snapshots = WorkspaceRestorer.snapshotAll(workspaces: [key: workspace])
        let restored = WorkspaceRestorer.restoreAll(
            from: snapshots,
            projects: [project],
            worktrees: [project.id: [worktree]]
        )
        let restoredTab = try #require(restored.first?.workspace.activeTab?.activeContent)
        let pane = try #require(restoredTab.content.pane)
        #expect(pane.title == "KajiCode")
        #expect(pane.startupCommand?.contains("kajicode") == true)
    }
}
