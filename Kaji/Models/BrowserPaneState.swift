import Foundation

@MainActor
@Observable
final class BrowserPaneState {
    static let defaultURL = "https://www.google.com"

    let projectPath: String
    let controllers = BrowserControllerRegistry()
    var pages: [BrowserPageState]
    var selectedPageID: UUID
    var selectedDeviceProfileID: String

    var selectedPage: BrowserPageState? {
        pages.first { $0.id == selectedPageID } ?? pages.first
    }

    var url: String {
        get { selectedPage?.url ?? Self.defaultURL }
        set { selectedPage?.url = newValue }
    }

    var title: String {
        get { selectedPage?.title ?? "Browser" }
        set { selectedPage?.title = newValue }
    }

    var pageSummary: String {
        get { selectedPage?.pageSummary ?? "" }
        set { selectedPage?.pageSummary = newValue }
    }

    init(projectPath: String, url: String = BrowserPaneState.defaultURL) {
        self.projectPath = projectPath
        let page = BrowserPageState(url: url)
        pages = [page]
        selectedPageID = page.id
        selectedDeviceProfileID = BrowserDeviceProfiles.desktopID
    }

    init(
        projectPath: String,
        pages: [BrowserPageState],
        selectedPageID: UUID?,
        selectedDeviceProfileID: String = BrowserDeviceProfiles.desktopID
    ) {
        self.projectPath = projectPath
        let restoredPages = pages.isEmpty ? [BrowserPageState()] : pages
        self.pages = restoredPages
        self.selectedPageID = selectedPageID.flatMap { id in
            restoredPages.contains { $0.id == id } ? id : nil
        } ?? restoredPages[0].id
        self.selectedDeviceProfileID = BrowserDeviceProfiles.profile(for: selectedDeviceProfileID).id
    }

    deinit {
        MainActor.assumeIsolated {
            controllers.closeAll()
        }
    }

    @discardableResult
    func openPage(url: String = BrowserPaneState.defaultURL) -> BrowserPageState {
        let page = BrowserPageState(url: url)
        pages.append(page)
        selectedPageID = page.id
        pruneInactiveControllers()
        return page
    }

    func selectPage(id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        selectedPageID = id
        pruneInactiveControllers()
    }

    func closePage(id: UUID) {
        guard pages.count > 1 else {
            controllers.removeController(for: pages[0].id)
            pages[0].url = Self.defaultURL
            pages[0].title = "Browser"
            pages[0].pageSummary = ""
            selectedPageID = pages[0].id
            return
        }
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages.remove(at: index)
        controllers.removeController(for: id)
        guard selectedPageID == id else { return }
        selectedPageID = pages[min(index, pages.count - 1)].id
        pruneInactiveControllers()
    }

    convenience init(projectPath: String, snapshot: TerminalTabSnapshot) {
        let pageSnapshots = snapshot.browserPages ?? []
        guard !pageSnapshots.isEmpty else {
            self.init(projectPath: projectPath, url: snapshot.browserURL ?? Self.defaultURL)
            return
        }
        self.init(
            projectPath: projectPath,
            pages: pageSnapshots.map { BrowserPageState(id: $0.id, url: $0.url, title: $0.title) },
            selectedPageID: snapshot.selectedBrowserPageID,
            selectedDeviceProfileID: snapshot.browserDeviceProfileID ?? BrowserDeviceProfiles.desktopID
        )
    }

    var pageSnapshots: [BrowserPageSnapshot] {
        pages.map { BrowserPageSnapshot(id: $0.id, url: $0.url, title: $0.title) }
    }

    func pruneInactiveControllers() {
        controllers.retainControllers(for: BrowserControllerRetentionPolicy.retainedControllerIDs(
            pageIDs: pages.map(\.id),
            selectedPageID: selectedPageID
        ))
    }
}
