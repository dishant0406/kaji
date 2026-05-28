import Foundation
import Testing

@testable import Kaji

@Suite("BrowserPaneState")
@MainActor
struct BrowserPaneStateTests {
    @Test("openPage selects a new browser page")
    func openPageSelectsNewPage() throws {
        let state = BrowserPaneState(projectPath: "/tmp/test")
        let firstID = state.selectedPageID

        let page = state.openPage(url: "https://example.com")

        #expect(state.pages.count == 2)
        #expect(state.selectedPageID == page.id)
        #expect(state.selectedPageID != firstID)
        #expect(state.url == "https://example.com")
    }

    @Test("state owns one stable controller registry")
    func stateOwnsStableControllerRegistry() {
        let state = BrowserPaneState(projectPath: "/tmp/test")
        let pageID = state.selectedPageID

        let first = state.controllers.controller(for: pageID)
        let second = state.controllers.controller(for: pageID)

        #expect(first === second)
    }

    @Test("selecting a browser page releases inactive controllers")
    func selectingBrowserPageReleasesInactiveControllers() throws {
        let state = BrowserPaneState(projectPath: "/tmp/test")
        let firstID = state.selectedPageID
        _ = state.controllers.controller(for: firstID)
        let secondPage = state.openPage(url: "https://second.example")
        _ = state.controllers.controller(for: secondPage.id)

        state.selectPage(id: firstID)
        _ = state.controllers.controller(for: firstID)

        #expect(state.controllers.controllerIDs == [firstID])
    }

    @Test("closePage keeps one reusable page")
    func closePageKeepsOneReusablePage() throws {
        let state = BrowserPaneState(projectPath: "/tmp/test", url: "https://example.com")
        let pageID = state.selectedPageID
        _ = state.controllers.controller(for: pageID)

        state.closePage(id: pageID)

        #expect(state.pages.count == 1)
        #expect(state.url == BrowserPaneState.defaultURL)
        #expect(state.title == "Browser")
        #expect(state.controllers.controllerIDs.isEmpty)
    }

    @Test("snapshot restore preserves browser pages and selection")
    func snapshotRestorePreservesPages() throws {
        let first = UUID()
        let second = UUID()
        let snapshot = TerminalTabSnapshot(
            kind: .browser,
            customTitle: nil,
            colorID: nil,
            isPinned: false,
            projectPath: "/tmp/test",
            paneTitle: "Browser",
            browserURL: "https://fallback.example",
            browserPages: [
                BrowserPageSnapshot(id: first, url: "https://one.example", title: "One"),
                BrowserPageSnapshot(id: second, url: "https://two.example", title: "Two"),
            ],
            selectedBrowserPageID: second
        )

        let state = BrowserPaneState(projectPath: "/tmp/test", snapshot: snapshot)

        #expect(state.pages.count == 2)
        #expect(state.selectedPageID == second)
        #expect(state.url == "https://two.example")
        #expect(state.title == "Two")
    }

    @Test("snapshot restore preserves selected browser device")
    func snapshotRestorePreservesSelectedBrowserDevice() throws {
        let snapshot = TerminalTabSnapshot(
            kind: .browser,
            customTitle: nil,
            colorID: nil,
            isPinned: false,
            projectPath: "/tmp/test",
            paneTitle: "Browser",
            browserURL: "https://example.com",
            browserPages: [
                BrowserPageSnapshot(id: UUID(), url: "https://example.com", title: "Example"),
            ],
            selectedBrowserPageID: nil,
            browserDeviceProfileID: "pixel-8"
        )

        let state = BrowserPaneState(projectPath: "/tmp/test", snapshot: snapshot)

        #expect(state.selectedDeviceProfileID == "pixel-8")
    }
}
