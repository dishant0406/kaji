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
            tabStrip
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

    private var tabStrip: some View {
        ViewThatFits(in: .horizontal) {
            tabStripContent(scrolls: false)
            ScrollView(.horizontal, showsIndicators: false) {
                tabStripContent(scrolls: true)
            }
        }
        .background(KajiTheme.secondaryBackground)
    }

    private func tabStripContent(scrolls: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(state.pages) { page in
                BrowserTabButton(
                    page: page,
                    selected: page.id == state.selectedPageID,
                    onSelect: {
                        state.selectPage(id: page.id)
                        pendingURL = page.url
                    },
                    onClose: { closeBrowserPage(page.id) }
                )
                .frame(maxWidth: scrolls ? nil : .infinity)
            }
            IconButton(symbol: "plus", accessibilityLabel: "New browser tab") {
                let page = state.openPage()
                pendingURL = page.url
                state.controllers.controller(for: page.id).ensureStarted(url: page.url)
            }
            .fixedSize()
            .help("New tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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

    private func closeBrowserPage(_ pageID: UUID) {
        guard state.pages.count > 1 else {
            state.controllers.closeAll()
            onClosePane()
            return
        }
        state.closePage(id: pageID)
        pendingURL = state.url
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
