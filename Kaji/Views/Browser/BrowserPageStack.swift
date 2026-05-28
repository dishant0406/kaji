import SwiftUI

struct BrowserPageStack: View {
    @Bindable var state: BrowserPaneState
    let paneIsVisible: Bool
    let deviceProfile: BrowserDeviceProfile
    let callbacks: BrowserSurfaceCallbacks

    var body: some View {
        ZStack {
            ForEach(mountedPages) { page in
                NativeBrowserSurface(
                    controller: state.controllers.controller(for: page.id),
                    page: page,
                    projectPath: state.projectPath,
                    isActive: BrowserPaneActivationPolicy.pageIsActive(
                        pageID: page.id,
                        selectedPageID: state.selectedPageID,
                        paneIsVisible: paneIsVisible
                    ),
                    deviceProfile: deviceProfile,
                    callbacks: callbacks
                )
                .opacity(page.id == state.selectedPageID ? 1 : 0)
                .allowsHitTesting(page.id == state.selectedPageID)
            }
        }
    }

    private var mountedPages: [BrowserPageState] {
        let mountedIDs = BrowserPageMountPolicy.mountedPageIDs(
            pageIDs: state.pages.map(\.id),
            selectedPageID: state.selectedPageID
        )
        return state.pages.filter { mountedIDs.contains($0.id) }
    }
}
