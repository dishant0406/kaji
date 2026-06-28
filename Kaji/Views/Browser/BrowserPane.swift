import SwiftUI

struct BrowserPane: View {
    @Bindable var state: BrowserPaneState
    let sessionID: String?
    let closeOnDisappear: Bool
    let managesBrowserControl: Bool
    let paneIsVisible: Bool
    let onClosePane: () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var pendingURL = ""
    @State var showsPageText = false
    @State var isReading = false
    private var selectedPage: BrowserPageState? { state.selectedPage }
    var selectedController: BrowserWebController? {
        selectedPage.map { state.controllers.controller(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabStrip(
                state: state,
                pendingURL: $pendingURL,
                onClosePane: onClosePane
            )
            toolbar
            Divider().overlay(KajiTheme.border)
            ZStack(alignment: .bottom) {
                pageStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if showsPageText {
                    BrowserPageTextPanel(
                        title: isReading ? "Reading page…" : "Page text",
                        text: state.pageSummary,
                        onClose: {
                            withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                                showsPageText = false
                            }
                        }
                    )
                    .transition(KajiMotion.bottomPanelTransition(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: showsPageText)
        }
        .background(KajiTheme.bg)
        .clipped()
        .task {
            state.controllers.cancelScheduledDiscard()
            pendingURL = state.url
            if managesBrowserControl {
                registerBrowserControl()
            }
        }
        .onDisappear {
            if managesBrowserControl {
                unregisterBrowserControl()
            }
            state.controllers.setActive(false)
            if closeOnDisappear {
                state.controllers.closeAll()
            } else {
                state.controllers.scheduleDiscard()
            }
        }
        .onChange(of: state.url) { _, newValue in
            pendingURL = newValue
        }
        .onChange(of: state.selectedPageID) { _, _ in
            pendingURL = state.url
            withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                showsPageText = false
            }
            startSelectedPageIfVisible()
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
            state.pruneInactiveControllers()
            if managesBrowserControl {
                registerBrowserControl()
            }
        }
        .onChange(of: state.selectedDeviceProfileID) { _, _ in
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
        }
        .onChange(of: paneIsVisible) { _, visible in
            guard visible else {
                state.controllers.setActive(false)
                if BrowserInactiveDiscardPolicy.shouldScheduleDiscard(
                    closeOnDisappear: closeOnDisappear,
                    paneIsVisible: visible
                ) {
                    state.controllers.scheduleDiscard()
                }
                return
            }
            state.controllers.cancelScheduledDiscard()
            startSelectedPageIfVisible()
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
        }
    }

    private var toolbar: some View {
        BrowserToolbar(
            pendingURL: $pendingURL,
            deviceProfileID: $state.selectedDeviceProfileID,
            showsPageText: showsPageText,
            onBack: { selectedController?.goBack() },
            onForward: { selectedController?.goForward() },
            onReload: { selectedController?.reload() },
            onNavigate: navigate,
            onReadPage: { Task { await readPage() } }
        )
    }

    private var pageStack: some View {
        BrowserPageStack(
            state: state,
            paneIsVisible: paneIsVisible,
            deviceProfile: selectedDeviceProfile,
            callbacks: BrowserSurfaceCallbacks(pageChanged: pageChanged, popupRequested: popupRequested)
        )
    }

    private func navigate() {
        selectedController?.navigate(to: pendingURL)
    }

    private func startSelectedPageIfVisible() {
        guard BrowserPaneActivationPolicy.shouldStartSelectedPage(paneIsVisible: paneIsVisible) else { return }
        selectedController?.ensureStarted(url: state.url)
    }

    private var selectedDeviceProfile: BrowserDeviceProfile {
        BrowserDeviceProfiles.profile(for: state.selectedDeviceProfileID)
    }

    private func pageChanged(pageID: UUID, url: String) {
        if pageID == state.selectedPageID, pendingURL != url {
            pendingURL = url
        }
    }

    private func popupRequested(pageID _: UUID, url: String) {
        let page = state.openPage(url: url.isEmpty ? "about:blank" : url)
        pendingURL = page.url
        state.controllers.controller(for: page.id).ensureStarted(url: page.url)
    }
}
