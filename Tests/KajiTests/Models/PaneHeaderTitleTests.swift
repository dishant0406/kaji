import Foundation
import Testing

@testable import Kaji

@Suite("PaneHeaderTitle")
@MainActor
struct PaneHeaderTitleTests {
    @Test("terminal prompt title resolves to working directory name")
    func promptTitleUsesDirectoryName() {
        let area = TabArea(projectPath: "/tmp/muxy")
        area.activeTab?.content.pane?.setTitle("dishants@host:~/projects/muxy/")

        let title = PaneHeaderTitle.resolve(for: area)

        #expect(title == "muxy")
    }

    @Test("default terminal title falls back to project name")
    func defaultTitleFallsBackToProjectName() {
        let area = TabArea(projectPath: "/tmp/muxy")

        let title = PaneHeaderTitle.resolve(for: area)

        #expect(title == "muxy")
    }

    @Test("vcs area uses source control label")
    func vcsUsesSourceControlLabel() {
        let area = TabArea(projectPath: "/tmp/muxy", existingTab: TerminalTab(vcsState: VCSTabState(projectPath: "/tmp/muxy")))

        let title = PaneHeaderTitle.resolve(for: area)

        #expect(title == "Source Control")
    }
}
