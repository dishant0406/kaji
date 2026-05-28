import Testing

@testable import Kaji

@Suite("TerminalTab inactive mount policy")
struct TerminalTabKindMountPolicyTests {
    @Test("keeps only stateful native surfaces mounted while inactive")
    func persistentKinds() {
        #expect(TerminalTab.Kind.terminal.keepsMountedWhenInactive)
        #expect(TerminalTab.Kind.browser.keepsMountedWhenInactive)
        #expect(TerminalTab.Kind.parentAgent.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.editor.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.filePreview.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.diffViewer.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.vcs.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.problems.keepsMountedWhenInactive)
        #expect(!TerminalTab.Kind.codeGraph.keepsMountedWhenInactive)
    }
}
