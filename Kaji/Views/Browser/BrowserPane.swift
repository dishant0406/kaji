import SwiftUI

struct BrowserPane: View {
    @Bindable var state: BrowserPaneState
    let sessionID: String?
    let closeOnDisappear: Bool
    let managesBrowserControl: Bool
    let paneIsVisible: Bool
    var respondsToKeyboardCommands = true
    let onClosePane: () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var pendingURL = ""
    @State private var addressFocusVersion = 0
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
        .onReceive(NotificationCenter.default.publisher(for: .browserBack)) { _ in
            guard canHandleBrowserCommand else { return }
            selectedController?.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserForward)) { _ in
            guard canHandleBrowserCommand else { return }
            selectedController?.goForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserReload)) { _ in
            guard canHandleBrowserCommand else { return }
            selectedController?.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserFocusAddressBar)) { _ in
            guard canHandleBrowserCommand else { return }
            addressFocusVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserNewPage)) { _ in
            guard canHandleBrowserCommand else { return }
            openPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserClosePage)) { _ in
            guard canHandleBrowserCommand else { return }
            closeSelectedPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserNextPage)) { _ in
            guard canHandleBrowserCommand else { return }
            selectPage(offset: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserPreviousPage)) { _ in
            guard canHandleBrowserCommand else { return }
            selectPage(offset: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserReadPage)) { _ in
            guard canHandleBrowserCommand else { return }
            Task { await readPage() }
        }
    }

    private var toolbar: some View {
        BrowserToolbar(
            pendingURL: $pendingURL,
            deviceProfileID: $state.selectedDeviceProfileID,
            addressFocusVersion: addressFocusVersion,
            showsPageText: showsPageText,
            onBack: { selectedController?.goBack() },
            onForward: { selectedController?.goForward() },
            onReload: { selectedController?.reload() },
            onNavigate: navigate,
            onReadPage: { Task { await readPage() } }
        )
    }

    private var canHandleBrowserCommand: Bool {
        paneIsVisible && respondsToKeyboardCommands
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

    private func openPage() {
        let page = state.openPage()
        pendingURL = page.url
        state.controllers.controller(for: page.id).ensureStarted(url: page.url)
        addressFocusVersion += 1
    }

    private func closeSelectedPage() {
        let pageID = state.selectedPageID
        guard state.pages.count > 1 else {
            state.controllers.closeAll()
            onClosePane()
            return
        }
        state.closePage(id: pageID)
        pendingURL = state.url
    }

    private func selectPage(offset: Int) {
        guard !state.pages.isEmpty else { return }
        let currentIndex = state.pages.firstIndex { $0.id == state.selectedPageID } ?? 0
        let targetIndex = (currentIndex + offset + state.pages.count) % state.pages.count
        let page = state.pages[targetIndex]
        state.selectPage(id: page.id)
        pendingURL = page.url
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
