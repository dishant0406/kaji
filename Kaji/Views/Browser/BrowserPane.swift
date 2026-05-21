import SwiftUI

struct BrowserPane: View {
    @Bindable var state: BrowserPaneState
    let sessionID: String?
    let closeOnDisappear: Bool
    let managesBrowserControl: Bool
    let onClosePane: () -> Void
    @State private var pendingURL = ""
    @State private var showsPageText = false
    @State private var isReading = false

    private var selectedPage: BrowserPageState? { state.selectedPage }
    private var selectedController: BrowserWebController? {
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
                        onClose: { showsPageText = false }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(KajiTheme.bg)
        .clipped()
        .task {
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
            }
        }
        .onChange(of: state.url) { _, newValue in
            pendingURL = newValue
        }
        .onChange(of: state.selectedPageID) { _, _ in
            pendingURL = state.url
            showsPageText = false
            selectedController?.ensureStarted(url: state.url)
            selectedController?.applyDeviceProfile(selectedDeviceProfile)
            if managesBrowserControl {
                registerBrowserControl()
            }
        }
        .onChange(of: state.selectedDeviceProfileID) { _, _ in
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
            onOpenDevTools: { selectedController?.showDevTools() },
            onReadPage: { Task { await readPage() } }
        )
    }

    private var pageStack: some View {
        ZStack {
            ForEach(state.pages) { page in
                NativeBrowserSurface(
                    controller: state.controllers.controller(for: page.id),
                    page: page,
                    projectPath: state.projectPath,
                    isActive: page.id == state.selectedPageID,
                    deviceProfile: selectedDeviceProfile,
                    callbacks: BrowserSurfaceCallbacks(pageChanged: pageChanged, popupRequested: popupRequested)
                )
                .opacity(page.id == state.selectedPageID ? 1 : 0)
                .allowsHitTesting(page.id == state.selectedPageID)
            }
        }
    }

    private func navigate() {
        selectedController?.navigate(to: pendingURL)
    }

    private var selectedDeviceProfile: BrowserDeviceProfile {
        BrowserDeviceProfiles.profile(for: state.selectedDeviceProfileID)
    }

    private func registerBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.register(
            sessionID: sessionID,
            state: state,
            controllers: state.controllers,
            close: onClosePane
        )
        KajiBrowserControlBroker.shared.updateSession(sessionID)
    }

    private func unregisterBrowserControl() {
        guard let sessionID else { return }
        KajiBrowserControlRegistry.shared.unregister(sessionID: sessionID)
    }

    private func closeBrowserPage(_ pageID: UUID) {
        guard state.pages.count > 1 else {
            state.controllers.closeAll()
            onClosePane()
            return
        }
        state.closePage(id: pageID)
        pendingURL = state.url
        state.controllers.removeController(for: pageID)
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

    private func readPage() async {
        isReading = true
        showsPageText = true
        defer { isReading = false }
        do {
            state.pageSummary = try await selectedController?.readPage() ?? ""
        } catch {
            state.pageSummary = error.localizedDescription
        }
    }
}
