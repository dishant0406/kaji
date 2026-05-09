import Foundation
import Testing

@testable import Droid

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
            selectedBrowserPageID: secondID
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)

        #expect(decoded.browserPages?.count == 2)
        #expect(decoded.browserPages?.last?.url == "https://two.example")
        #expect(decoded.selectedBrowserPageID == secondID)
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
}
